#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
# test-wave-build.sh — hermetic self-tests for automate-wave.sh `wave-build` (the one writer of a wave
# branch). Fixture: a bare fake origin + a "primary" clone holding the items, a stub
# scripts/ci-local.sh + scripts/bump-version.sh and a plugin.json; lanes made by the REAL
# `automate-lanes.sh lane-create` (meta-sync / setup-memory / policy stubbed through its seams), each
# lane's feature branch pushed to the fake origin and its run file parked by hand. `gh` is a PATH stub
# answering `pr view`, `pr list` and `pr create` (argv recorded) — any `pr merge` or `api` call is
# recorded as FORBIDDEN and fails the suite. The real automate-helpers.sh runs progress-append and
# reconcile-item. No network, no real gh.
#
# Groups: W1 happy path (base, planner order, exact shas, ci in the worktree, release last, push, one
#   pr create, Progress line, worktree removed, primary byte-identical) · W2 idempotent re-run (done) ·
#   W3 refusals (PR not OPEN, lane not parked, branch on origin, local branch, live lock) — nothing
#   created · W4 STOPs (ci failure, bump failure, conflict) — nothing pushed, worktree kept · W5 no
#   ci-local / no bump-version ⇒ skipped lines, PR still opened · W6 static guards + mutation controls
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/automate-wave.sh"
L="$HERE/automate-lanes.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
SLEEP_PID=""
cleanup() { [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$(printf '%s' "$2" | head -c 900)]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3]" ;; *) ok "$1" ;; esac; }

export HOME="$T/home"; mkdir -p "$HOME" "$T/tmp"
export TMPDIR="$T/tmp"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1
unset LOOMWRIGHT_GH_BIN LOOMWRIGHT_LANES_HELPERS
export WB_T="$T"

# ---- stubs ------------------------------------------------------------------------------------------
BIN="$T/bin"; mkdir -p "$BIN" "$T/gh"
echo '[]' > "$T/gh/prs.json"
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
G="$WB_T/gh"; echo "gh $*" >> "$G/calls"
case "$1 ${2:-}" in
  "pr view")
    n="${3##*/}"; st="$(cat "$G/state.$n" 2>/dev/null)"; st="${st:-OPEN}"; sha="$(cat "$G/head.$n" 2>/dev/null)"
    ma=null; [ "$st" = MERGED ] && ma='"2026-10-11T00:00:00Z"'
    printf '{"state":"%s","mergedAt":%s,"headRefOid":"%s"}\n' "$st" "$ma" "$sha" ;;
  "pr list")
    [ -n "${STUB_LIST_FAIL:-}" ] && exit 1
    h=""; while [ "$#" -gt 0 ]; do [ "$1" = --head ] && h="$2"; shift; done
    jq -c --arg h "$h" '[.[] | select(.headRefName == $h)]' "$G/prs.json" ;;
  "pr create")
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "gh $*" >> "$G/create-failed"; echo "pull request create failed: stub" >&2; exit 1; }
    k="$(ls "$G" | grep -c '^create\.')"; k=$((k + 1)); h=""
    for a in "$@"; do printf '%s\n' "$a"; done > "$G/create.$k"
    while [ "$#" -gt 0 ]; do [ "$1" = --head ] && h="$2"; shift; done
    url="https://github.com/o/r/pull/$((900 + k))"
    jq -c --arg h "$h" --arg u "$url" --argjson n "$((900 + k))" '. + [{number: $n, url: $u, state: "OPEN", headRefName: $h}]' \
      "$G/prs.json" > "$G/prs.tmp" && mv "$G/prs.tmp" "$G/prs.json"
    echo "$url" ;;
  "pr merge"|"api "*) echo "FORBIDDEN gh $*" >> "$G/FORBIDDEN"; exit 1 ;;
  *) echo "FORBIDDEN-UNKNOWN gh $*" >> "$G/FORBIDDEN"; exit 1 ;;
esac
EOF
cat > "$T/meta-sync.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$T/setup-memory.sh" <<'EOF'
#!/usr/bin/env bash
echo off
EOF
cat > "$T/policy.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/gh" "$T"/*.sh
export PATH="$BIN:$PATH"
export LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_SETUP_MEMORY="$T/setup-memory.sh" LOOMWRIGHT_LANES_POLICY="$T/policy.sh"

# ---- fixture: origin + primary ------------------------------------------------------------------------
ORIGIN="$T/origin.git"; P="$T/work/primary"
git init -q --bare "$ORIGIN"; git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
git init -q "$P"; git -C "$P" checkout -q -b main
printf '.supervisor/*\n.claude/settings.local.json\n' > "$P/.gitignore"
IA="reqs/parallel-automate/21-a.md"; IB="reqs/parallel-automate/22-b.md"
mkdir -p "$P/reqs/parallel-automate" "$P/scripts" "$P/loomwright/.claude-plugin" "$P/changelog.d"
echo "# a" > "$P/$IA"; echo "# b" > "$P/$IB"; echo base > "$P/shared.txt"
printf '{\n  "name": "fixture",\n  "version": "1.0.0"\n}\n' > "$P/loomwright/.claude-plugin/plugin.json"
printf '<!-- bump: minor -->\nfixture fragment\nbody\n' > "$P/changelog.d/x.md"
cat > "$P/scripts/ci-local.sh" <<'EOF'
#!/usr/bin/env bash
echo "$PWD" >> "$WB_T/ci.calls"
if [ "${STUB_CI_RC:-0}" = 0 ]; then echo "ci-local: PASS (stub)"; exit 0; fi
echo "ci-local: FAIL (stub)"; exit "$STUB_CI_RC"
EOF
cat > "$P/scripts/bump-version.sh" <<'EOF'
#!/usr/bin/env bash
echo "$PWD" >> "$WB_T/bump.calls"
if [ "${STUB_BUMP_RC:-0}" != 0 ]; then echo "bump-version: refused — stub failure"; exit "$STUB_BUMP_RC"; fi
sed 's/"1.0.0"/"1.1.0"/' loomwright/.claude-plugin/plugin.json > plugin.tmp && mv plugin.tmp loomwright/.claude-plugin/plugin.json
rm -f changelog.d/x.md
echo "bump-version: bumped 1.0.0 -> 1.1.0 (minor, from fragments); folded 1 fragment(s): changelog.d/x.md"
EOF
git -C "$P" add -A; git -C "$P" commit -qm init
git -C "$P" remote add origin "$ORIGIN"; git -C "$P" push -q -u origin main 2>/dev/null
git -C "$P" remote set-head origin -a >/dev/null 2>&1
mkdir -p "$P/.supervisor/automate"
MAIN0="$(git -C "$P" rev-parse HEAD)"

# mk_parent <run_id> [<## Current wave line>] — a parent run file
mk_parent() {
  printf '# Automate Run: %s\n\n## Status: running\n\n## Run Config\n- parallel: 2\n\n## Queue\n- [ ] %s\n- [ ] %s\n\n## Current\n- item: null | status: null\n%s\n## Progress\n' \
    "$1" "$IA" "$IB" "${2:+$2
}" > "$P/.supervisor/automate/$1.md"
}
# mk_lane <parent> <n> <item> <pr number> <file> <content> — lane-create, then a pushed feature branch
# carrying one commit, the lane table row moved to `launched`, the run file parked awaiting_merge.
mk_lane() {
  local parent="$1" n="$2" item="$3" pr="$4" f="$5" c="$6" d tbl
  bash "$L" lane-create "$P/.supervisor/automate/$parent.md" "$item" "$n" >/dev/null 2>&1 || bad "lane-create $parent L$n"
  d="$T/work/primary-lanes/$parent/L$n"; tbl="$P/.supervisor/automate/$parent.lanes"
  git -C "$d" checkout -q -b "feature/$parent-$n"; echo "$c" > "$d/$f"; git -C "$d" add "$f"; git -C "$d" commit -qm "lane $n work"
  git -C "$d" push -q origin "feature/$parent-$n" 2>/dev/null
  git -C "$d" rev-parse HEAD > "$T/gh/head.$pr"
  awk -F'\t' -v OFS='\t' -v l="L$n" '$1 == l { $8 = "launched" } { print }' "$tbl" > "$tbl.tmp" && mv "$tbl.tmp" "$tbl"
  park_lane "$parent" "$n" "$item" "$pr" awaiting_merge awaiting_merge
}
park_lane() { # <parent> <n> <item> <pr> <status> <pause_reason>
  printf '# Automate Run: %s-L%s\n\n## Status: paused\n\n## Queue\n- [ ] %s\n\n## Current\n- item: %s | status: %s | pr: https://github.com/o/r/pull/%s | branch: feature/x\n- pause_reason: %s\n\n## Progress\n' \
    "$1" "$2" "$3" "$3" "$5" "$4" "$6" > "$T/work/primary-lanes/$1/L$2/.supervisor/automate/$1-L$2.md"
}
wb() { bash "$S" wave-build "$@" 2>&1; }
pstate() { printf '%s|%s|%s\n' "$(git -C "$P" symbolic-ref HEAD)" "$(git -C "$P" rev-parse HEAD)" "$(git -C "$P" status --porcelain --untracked-files=all)"; git -C "$P" ls-files -s | cksum; }
refs_state() { git -C "$P" for-each-ref --format='%(refname) %(objectname)' refs/heads; git -C "$P" worktree list --porcelain; git --git-dir="$ORIGIN" for-each-ref; } 2>/dev/null
origin_has() { git --git-dir="$ORIGIN" rev-parse -q --verify "refs/heads/$1" >/dev/null 2>&1 && echo yes || echo no; }
ncreate() { ls "$T/gh" | grep -c '^create\.' | tr -d ' '; }
kept_wt() { printf '%s\n' "$1" | sed -n 's/.*worktree kept at \(.*\)$/\1/p' | tail -1; }
drop_local() { # <worktree> <branch> — the owner's hand cleanup after a STOP
  [ -n "$1" ] && git -C "$P" worktree remove --force "$1" >/dev/null 2>&1; git -C "$P" branch -D "$2" >/dev/null 2>&1; rm -rf "$(dirname "${1:-/nonexistent}")"
}

A=automate-2026-10-11-100000; RFA="$P/.supervisor/automate/$A.md"
mk_parent "$A" "- wave: 3 | items: $IB, $IA"
mk_lane "$A" 1 "$IA" 11 a.txt "lane one"
mk_lane "$A" 2 "$IB" 12 b.txt "lane two"
SHA11="$(cat "$T/gh/head.11")"; SHA12="$(cat "$T/gh/head.12")"

# ---- W1: happy path ---------------------------------------------------------------------------------
P0="$(pstate)"
out="$(wb "$RFA")"; rc=$?
printf '%s\n' "$out" | sed 's/^/       | /'
WBR="wave/$A-w3"
check "W1 exit 0, last line names the opened PR" "$rc:$(printf '%s\n' "$out" | tail -n1)" "0:wave-build: opened — https://github.com/o/r/pull/901"
check "W1b the wave branch is on origin" "$(origin_has "$WBR")" yes
FP="$(git --git-dir="$ORIGIN" log --first-parent --reverse --format='%P|%s' "main..$WBR")"
check "W1c off origin/main: two --no-ff merges in PLANNER order with the exact head shas, then the release commit LAST" "$FP" \
"$MAIN0 $SHA12|Merge lane L2 ($IB) PR #12
$(git --git-dir="$ORIGIN" rev-parse "$WBR~2") $SHA11|Merge lane L1 ($IA) PR #11
$(git --git-dir="$ORIGIN" rev-parse "$WBR~1")|chore(release): v1.1.0 — fold wave 3 fragments (pa/22, pa/21)"
# A script makes this commit, not a model: no model co-author trailer (claude-review, PR #473).
check "W1d the release commit carries no Co-Authored-By trailer" "$(git --git-dir="$ORIGIN" log -1 --format=%B "$WBR" | grep -c '^Co-Authored-By:' | tr -d ' ')" 0
check "W1e the release commit carries the bump (plugin.json 1.1.0, fragment folded)" \
  "$(git --git-dir="$ORIGIN" show "$WBR:loomwright/.claude-plugin/plugin.json" | jq -r .version):$(git --git-dir="$ORIGIN" ls-tree --name-only "$WBR" changelog.d/ | wc -l | tr -d ' ')" "1.1.0:0"
CIP="$(head -1 "$T/ci.calls" 2>/dev/null)"
case "$CIP" in "$T/tmp/automate-wave-$A-w3."*/wt) ok "W1f ci-local ran inside the temporary worktree ($CIP)" ;; *) bad "W1f ci-local ran inside the temporary worktree" "got [$CIP]" ;; esac
check "W1g … and bump-version in the same worktree" "$(head -1 "$T/bump.calls" 2>/dev/null)" "$CIP"
check "W1h gh pr create called exactly once" "$(ncreate)" 1
check "W1i … with --base main --head <wave branch> and the title" \
  "$(awk 'p == "--base" || p == "--head" || p == "--title" { print p "=" $0 } { p = $0 }' "$T/gh/create.1" | paste -sd '|' -)" \
  "--base=main|--head=$WBR|--title=Wave 3 ($A): pa/22, pa/21"
BODY="$(cat "$T/gh/create.1")"
has "W1j body lists each lane with its merged head sha" "$BODY" "| L2 | \`$IB\` | #12 | \`$SHA12\` |"
has "W1j2 … in planner order" "$(printf '%s\n' "$BODY" | grep -n '^| L' | paste -sd ' ' -)" "| L2 "
has "W1k body: local CI result" "$BODY" "Local CI: pass"
has "W1l body: release commit" "$BODY" "v1.1.0 (\`scripts/bump-version.sh\`), the last commit"
has "W1m body: merging marks the lane PRs merged, then --resume runs fleet-closeout" "$BODY" "\`/automate --resume $A\` runs \`fleet-closeout\`"
check "W1n body ends with the Claude Code line" "$(tail -n1 "$T/gh/create.1")" "🤖 Generated with [Claude Code](https://claude.com/claude-code)"
check "W1o ONE parent Progress line, timestamped like every other" "$(grep -cE -- "^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z wave built: $WBR — PR https://github.com/o/r/pull/901 \(lanes: L2 PR #12, L1 PR #11; ci pass; release v1\.1\.0\)$" "$RFA" | tr -d ' ')" 1
WT1="$(printf '%s\n' "$out" | sed -n 's/^wave-build: worktree — \([^ ]*\) on .*/\1/p')"
check "W1p the temporary worktree is removed (and its tmp dir), the branch kept locally" \
  "$([ -e "$WT1" ] && echo kept || echo gone):$([ -e "$(dirname "$WT1")" ] && echo kept || echo gone):$(git -C "$P" worktree list | wc -l | tr -d ' '):$(git -C "$P" rev-parse "$WBR")" \
  "gone:gone:1:$(git --git-dir="$ORIGIN" rev-parse "$WBR")"
check "W1q GUARD: the primary's branch, HEAD, status and index are byte-identical" "$(pstate)" "$P0"
check "W1r the wave-build lock is released" "$([ -e "$P/.supervisor/automate/$A.wave-build.lock" ] && echo held || echo free)" free
check "W1s no lane branch was touched on origin" "$(git --git-dir="$ORIGIN" rev-parse "feature/$A-1"):$(git --git-dir="$ORIGIN" rev-parse "feature/$A-2")" "$SHA11:$SHA12"
check "W1t one line per step, in order" "$(printf '%s\n' "$out" | sed -n 's/^wave-build: \([a-z]*\) — .*/\1/p' | paste -sd ' ' -)" \
  "worktree merge merge ci release push record cleanup opened"

# ---- W2: idempotent re-run (through the helpers dispatcher) -----------------------------------------
R0="$(refs_state)"; SP="$(cksum < "$RFA")"
out="$(bash "$HERE/automate-helpers.sh" wave-build "$RFA" 2>&1)"; rc=$?
check "W2 re-run with the wave PR open ⇒ done, exit 0 (via automate-helpers.sh)" "$rc:$out" "0:wave-build: done — wave PR https://github.com/o/r/pull/901 already open"
check "W2b … no new commit, ref, worktree or PR; the parent run file byte-unchanged" "$(refs_state):$(ncreate):$(cksum < "$RFA")" "$R0:1:$SP"

# ---- W3: refusals — exit 1, nothing created ---------------------------------------------------------
R0="$(refs_state)"
echo MERGED > "$T/gh/state.12"
out="$(wb "$RFA" --wave-branch wave/not-open)"; rc=$?
check "W3 a lane PR not OPEN ⇒ refused, exit 1" "$rc:$(printf '%s\n' "$out" | grep -cxF 'wave-build: refused — L2 PR #12 is MERGED, not OPEN' | tr -d ' ')" "1:1"
check "W3b … nothing created (refs, worktrees, origin), no pr create" "$(refs_state):$(ncreate)" "$R0:1"
rm -f "$T/gh/state.12"
park_lane "$A" 1 "$IA" 11 running null
out="$(wb "$RFA" --wave-branch wave/not-parked)"; rc=$?
check "W3c a lane not parked ⇒ refused naming lane-status's state, exit 1" "$rc:$(printf '%s\n' "$out" | grep -c '^wave-build: refused — L1 is not parked (lane-status reads stalled; ' | tr -d ' ')" "1:1"
check "W3d … nothing created" "$(refs_state):$(ncreate)" "$R0:1"
park_lane "$A" 1 "$IA" 11 ready_for_release ready_for_release
out="$(wb "$RFA" --wave-branch wave/rfr-ok --help-not-a-flag)"; rc=$?
check "W3e an unknown flag is refused, exit 1" "$rc:$out" "1:wave-build: refused — unknown flag '--help-not-a-flag'"
git -C "$P" push -q origin "main:refs/heads/wave/exists" 2>/dev/null; R0="$(refs_state)"
out="$(wb "$RFA" --wave-branch wave/exists)"; rc=$?
check "W3f the wave branch already on origin with no open PR ⇒ refused, exit 1, nothing created" \
  "$rc:$(printf '%s\n' "$out" | grep -c '^wave-build: refused — wave/exists already exists on origin with no open PR' | tr -d ' '):$(refs_state)" "1:1:$R0"
git -C "$P" branch wave/local-only "$MAIN0"; R0="$(refs_state)"
out="$(wb "$RFA" --wave-branch wave/local-only)"; rc=$?
check "W3g a local branch of that name (a STOPPED build's) ⇒ refused, exit 1, nothing created" \
  "$rc:$(printf '%s\n' "$out" | grep -c '^wave-build: refused — local branch wave/local-only already exists' | tr -d ' '):$(refs_state)" "1:1:$R0"
git -C "$P" branch -D wave/local-only >/dev/null
out="$(STUB_LIST_FAIL=1 wb "$RFA" --wave-branch wave/list-fail)"; rc=$?
check "W3h gh pr list unreadable ⇒ refused (fail closed), exit 1" "$rc:$(printf '%s\n' "$out" | grep -c '^wave-build: refused — cannot read the PRs from wave/list-fail' | tr -d ' ')" "1:1"
# a LIVE holder of the wave-build lock refuses (no wait); a dead holder's lock is reclaimed
sleep 30 & SLEEP_PID=$!
mkdir "$P/.supervisor/automate/$A.wave-build.lock"
printf '%s %s\n' "$SLEEP_PID" "$(env LC_ALL=C ps -o lstart= -p "$SLEEP_PID" | tr -s ' ' | sed 's/^ //; s/ $//')" > "$P/.supervisor/automate/$A.wave-build.lock/holder"
out="$(LOOMWRIGHT_WAVE_LOCK_WAIT_S=0 wb "$RFA" --wave-branch wave/locked)"; rc=$?
check "W3i a live wave-build lock holder ⇒ refused naming it, exit 1" "$rc:$(printf '%s\n' "$out" | grep -c "^wave-build: refused — another wave-build for $A is running (lock .*holder pid $SLEEP_PID)" | tr -d ' ')" "1:1"
check "W3j … the foreign lock is left alone" "$(cat "$P/.supervisor/automate/$A.wave-build.lock/holder" | cut -d' ' -f1)" "$SLEEP_PID"
kill "$SLEEP_PID" 2>/dev/null; wait "$SLEEP_PID" 2>/dev/null; SLEEP_PID=""
out="$(LOOMWRIGHT_WAVE_LOCK_WAIT_S=0 wb "$RFA" --wave-branch wave/exists)"
has "W3k a dead holder's lock is reclaimed (the run reaches the next refusal)" "$out" "wave-build: refused — wave/exists already exists on origin"
check "W3l … and released again" "$([ -e "$P/.supervisor/automate/$A.wave-build.lock" ] && echo held || echo free)" free
check "W3m usage with no parent run file ⇒ refused, exit 1" "$(wb; echo "rc=$?")" "wave-build: refused — usage: wave-build <parent_runfile> [--wave-branch <name>]
rc=1"

# ---- W4: STOPs — exit 2, nothing pushed, worktree kept -----------------------------------------------
P0="$(pstate)"
out="$(STUB_CI_RC=1 wb "$RFA" --wave-branch wave/ci-fail)"; rc=$?
KW="$(kept_wt "$out")"
check "W4 a failing local CI ⇒ STOPPED, exit 2" "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '^wave-build: STOPPED — local CI failed (exit 1: ci-local: FAIL (stub)) — log .*/ci-local.log; nothing pushed; worktree kept at ' | tr -d ' ')" "2:1"
check "W4b … nothing pushed, no pr create, the worktree kept (both merges in it), lock released" \
  "$(origin_has wave/ci-fail):$(ncreate):$([ -d "$KW" ] && git -C "$KW" log --merges --format=%s origin/main..HEAD | wc -l | tr -d ' '):$([ -e "$P/.supervisor/automate/$A.wave-build.lock" ] && echo held || echo free)" "no:1:2:free"
check "W4c … the primary is byte-identical" "$(pstate)" "$P0"
drop_local "$KW" wave/ci-fail
out="$(STUB_BUMP_RC=1 wb "$RFA" --wave-branch wave/bump-fail)"; rc=$?
KW="$(kept_wt "$out")"
check "W4d a failing release step ⇒ STOPPED, exit 2, nothing pushed, no pr create" \
  "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '^wave-build: STOPPED — release step failed (bump-version.sh exit 1: bump-version: refused — stub failure)' | tr -d ' '):$(origin_has wave/bump-fail):$(ncreate):$([ -d "$KW" ] && echo kept)" "2:1:no:1:kept"
drop_local "$KW" wave/bump-fail
B=automate-2026-10-11-110000; RFB="$P/.supervisor/automate/$B.md"
mk_parent "$B"
mk_lane "$B" 1 "$IA" 21 shared.txt "one side"
mk_lane "$B" 2 "$IB" 22 shared.txt "other side"
out="$(wb "$RFB")"; rc=$?
KW="$(kept_wt "$out")"
check "W4e a conflict ⇒ STOPPED naming the lane, PR and files, exit 2 (lane-table order, wave 1)" \
  "$rc:$(printf '%s\n' "$out" | tail -n1)" \
  "2:wave-build: STOPPED — conflict merging L2 (PR #22) in shared.txt — integrate by hand per wave-plan's conflict rules; worktree kept at $KW"
check "W4f … merge aborted (clean, no MERGE_HEAD), L1 merged before it, nothing pushed, no pr create, ci never ran" \
  "$(git -C "$KW" status --porcelain | wc -l | tr -d ' '):$(git -C "$KW" rev-parse -q --verify MERGE_HEAD >/dev/null && echo merging || echo none):$(git -C "$KW" log --merges --format=%s origin/main..HEAD):$(origin_has "wave/$B-w1"):$(ncreate):$(wc -l < "$T/ci.calls" | tr -d ' ')" \
  "0:none:Merge lane L1 ($IA) PR #21:no:1:3"
drop_local "$KW" "wave/$B-w1"
NP="$(grep -c 'wave built:' "$RFA" | tr -d ' ')"
out="$(STUB_CREATE_FAIL=1 wb "$RFA" --wave-branch wave/create-fail)"; rc=$?
KW="$(kept_wt "$out")"
check "W4g gh pr create failing AFTER the push ⇒ STOPPED, exit 2, naming the pushed branch and the command" \
  "$rc:$(printf '%s\n' "$out" | tail -n1 | grep -c '^wave-build: STOPPED — gh pr create failed: .* — wave/create-fail IS pushed; open the PR by hand: gh pr create --base main --head wave/create-fail; worktree kept at ' | tr -d ' ')" "2:1"
check "W4h … the branch is on origin, no PR recorded, no Progress line, the worktree kept" \
  "$(origin_has wave/create-fail):$(jq 'length' "$T/gh/prs.json"):$(grep -c 'wave built:' "$RFA" | tr -d ' '):$([ -d "$KW" ] && echo kept)" "yes:1:$NP:kept"
out="$(wb "$RFA" --wave-branch wave/create-fail)"; rc=$?
check "W4i … and a re-run refuses on the pushed branch (no second push, no duplicate PR)" \
  "$rc:$(printf '%s\n' "$out" | grep -c '^wave-build: refused — wave/create-fail already exists on origin with no open PR' | tr -d ' ')" "1:1"
drop_local "$KW" wave/create-fail

# ---- W5: no scripts/ci-local.sh, no scripts/bump-version.sh — skipped, PR still opened ---------------
git clone -q "$ORIGIN" "$T/other" 2>/dev/null; git -C "$T/other" rm -q -r scripts; git -C "$T/other" commit -qm "drop scripts"; git -C "$T/other" push -q origin main 2>/dev/null
NC0="$(wc -l < "$T/ci.calls" | tr -d ' ')"
out="$(wb "$RFA" --wave-branch wave/noscripts)"; rc=$?
has "W5 ci skipped line" "$out" "wave-build: ci — skipped (no scripts/ci-local.sh; the wave PR's CI is the gate)"
has "W5b release skipped line" "$out" "wave-build: release — skipped (no scripts/bump-version.sh; run this project's release step on the wave branch)"
check "W5c … the PR is still opened, exit 0; the last commit is the last merge; Progress line says skipped" \
  "$rc:$(printf '%s\n' "$out" | tail -n1):$(git --git-dir="$ORIGIN" log -1 --format=%s wave/noscripts):$(grep -c 'wave built: wave/noscripts — PR https://github.com/o/r/pull/902 (lanes: L2 PR #12, L1 PR #11; ci skipped; release skipped)$' "$RFA" | tr -d ' '):$(wc -l < "$T/ci.calls" | tr -d ' ')" \
  "0:wave-build: opened — https://github.com/o/r/pull/902:Merge lane L1 ($IA) PR #11:1:$NC0"
check "W5d gh was never asked to merge (no pr merge / api call in the whole suite)" "$(cat "$T/gh/FORBIDDEN" 2>/dev/null)" ""

# ---- W6: static guards + mutation controls ------------------------------------------------------------
noncomment() { grep -nE "$1" "$2" | grep -vE '^[0-9]+:[[:space:]]*#'; }
g_merge() { noncomment 'pr[[:space:]]+merge|merge[[:space:]]+--squash|--admin' "$1"; }
g_force() { noncomment 'git( -C "[^"]*")? push' "$1" | grep -E -- '--force|(^|[[:space:]])-f([[:space:]]|$)|[[:space:]]"?\+|--mirror|--delete|--all|--tags'; }
g_pushes() { noncomment 'git( -C "[^"]*")? push' "$1"; }
g_push_target() { g_pushes "$1" | grep -vE 'push[[:space:]]+(-q[[:space:]]+)?(-u[[:space:]]+)?origin[[:space:]]+"\$wb"[[:space:]]+2>&1'; }
check "W6 automate-wave.sh has no executable PR merge (pr merge / --squash / --admin)" "$(g_merge "$S")" ""
check "W6b … no force / mirror / delete / +refspec push" "$(g_force "$S")" ""
check "W6c … exactly one git push, and it names only the wave-branch variable" "$(g_pushes "$S" | wc -l | tr -d ' '):$(g_push_target "$S")" "1:"
# W6d reads the lanes code through the entry point's own _lanes_bundle (the entry with every
# automate-lanes.d/ module expanded at its source point — ONE file, so `grep -n` keeps its `N:` prefix
# and the comment filter still matches): the guard covers the modules, not just the thin entry point.
# Its input is automate-lanes.sh + the automate-lanes.d/*.sh modules it sources by name.
w6d_hits() { grep -nE 'gh pr merge|gate-eval|git( -C [^ ]+)? (merge|push)( |$)' "$1" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vE 'LANE_DISALLOWED_FIXED=|disallow="|echo "git |printf .git merge'; }
eval "$(awk '/^_lanes_bundle\(\) \{$/,/^}$/' "$L")"
LB="$T/automate-lanes.bundle.sh"
_lanes_bundle "$L" > "$LB" && [ -s "$LB" ] && bash -n "$LB" || bad "W6d could not build the automate-lanes.sh bundle (entry + automate-lanes.d/)"
check "W6d automate-lanes.sh still has no executable git merge / push (AG6's shape)" \
  "$(w6d_hits "$LB")" ""
MUT="$T/mut"; mkdir -p "$MUT"
# W6d2 planted violation: an executable push in one automate-lanes.d/ MODULE (scratch copy) must be
# reported by W6d's input — proof the guard reads the modules
mkdir -p "$MUT/lanes"; cp "$L" "$MUT/lanes/"; cp -R "$HERE/automate-lanes.d" "$MUT/lanes/"
printf '%s\n' '  git push origin HEAD' >> "$MUT/lanes/automate-lanes.d/wave.sh"
_lanes_bundle "$MUT/lanes/automate-lanes.sh" > "$MUT/lanes.bundle.sh"
if ! cmp -s "$HERE/automate-lanes.d/wave.sh" "$MUT/lanes/automate-lanes.d/wave.sh" && [ -s "$MUT/lanes.bundle.sh" ] && bash -n "$MUT/lanes.bundle.sh"; then
  ok "W6d2 module mutant valid (differs, bundle non-empty, bash -n)"; else bad "W6d2 module mutant invalid"; fi
check "W6d3 mutation (an executable git push in automate-lanes.d/wave.sh) is caught by W6d's input" \
  "$(w6d_hits "$MUT/lanes.bundle.sh" | sed 's/^[0-9]*://')" "  git push origin HEAD"
mut_ok() { [ -s "$1" ] && ! cmp -s "$S" "$1" && bash -n "$1"; }
awk '{ print } /^  # 10. the wave PR$/ { print "  \"$LANES_GH\" pr merge \"$wb\" --merge >/dev/null 2>&1" }' "$S" > "$MUT/m1.sh"
if mut_ok "$MUT/m1.sh"; then ok "W6e mutant 1 valid (non-empty, differs, bash -n)"; else bad "W6e mutant 1 invalid"; fi
check "W6f mutation (an executable gh pr merge) is caught" "$(g_merge "$MUT/m1.sh" | wc -l | tr -d ' ')" 1
sed 's/push -q -u origin "\$wb"/push -q --force -u origin "$wb"/' "$S" > "$MUT/m2.sh"
if mut_ok "$MUT/m2.sh"; then ok "W6g mutant 2 valid"; else bad "W6g mutant 2 invalid"; fi
check "W6h mutation (a force push) is caught" "$(g_force "$MUT/m2.sh" | wc -l | tr -d ' ')" 1
awk '{ print } /^  # 9. push/ { print "  git -C \"$wt\" push -q origin \"HEAD:refs/heads/$base\" >/dev/null 2>&1" }' "$S" > "$MUT/m3.sh"
if mut_ok "$MUT/m3.sh"; then ok "W6i mutant 3 valid"; else bad "W6i mutant 3 invalid"; fi
check "W6j mutation (a push of another ref) is caught" "$(g_push_target "$MUT/m3.sh" | wc -l | tr -d ' ')" 1
sed 's/push -q -u origin "\$wb"/push -q -u origin "+$wb"/' "$S" > "$MUT/m4.sh"
if mut_ok "$MUT/m4.sh"; then ok "W6k mutant 4 valid"; else bad "W6k mutant 4 invalid"; fi
check "W6l mutation (a +refspec force push) is caught by both guards" "$(g_force "$MUT/m4.sh" | wc -l | tr -d ' '):$(g_push_target "$MUT/m4.sh" | wc -l | tr -d ' ')" "1:1"
# (the needle is assembled at run time: CLAUDE.md's sanctioned-executor grep must not count this file)
SQ="$(printf 'gh pr %s --%s' merge squash)"
check "W6m the literal squash-merge command string appears nowhere in automate-wave.sh" "$(grep -cF -- "$SQ" "$S" | tr -d ' ')" 0
check "W6n helpers dispatches wave-build to automate-wave.sh (one arm)" \
  "$(grep -cE '^ +wave-build\) exec bash "\$\(dirname "\$0"\)/automate-wave.sh" "\$cmd" "\$@" ;;$' "$HERE/automate-helpers.sh" | tr -d ' ')" 1

# ---- W7: single-lane mode (`--parallel 1`, twin-remediation/08b) — no wave, no wave PR ------------------
SLP=automate-2026-10-14-100000; RFSL="$P/.supervisor/automate/$SLP.md"
mk_parent "$SLP"; sed 's/^- parallel: 2$/- parallel: 1/' "$RFSL" > "$RFSL.tmp" && mv "$RFSL.tmp" "$RFSL"
bash "$L" lane-create "$RFSL" "$IA" 1 --parallel 1 >/dev/null 2>&1 || bad "W7 lane-create --parallel 1"
park_lane "$SLP" 1 "$IA" 71 awaiting_merge awaiting_merge
R7="$(refs_state)"; N7="$(ncreate)"; S7="$(cksum < "$RFSL")"; G7="$(cat "$T/gh/calls" 2>/dev/null | wc -l | tr -d ' ')"
out="$(wb "$RFSL")"; rc=$?
check "W7 a parent whose Run Config carries - parallel: 1 ⇒ refused single-lane mode (no wave PR), exit 1" "$rc:$out" \
  "1:wave-build: refused — single-lane mode (no wave PR)"
check "W7b … nothing created or read: refs, worktrees, origin, PRs, gh calls and the parent run file unchanged" \
  "$(refs_state):$(ncreate):$(cksum < "$RFSL"):$(cat "$T/gh/calls" 2>/dev/null | wc -l | tr -d ' ')" "$R7:$N7:$S7:$G7"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
