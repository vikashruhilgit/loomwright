#!/usr/bin/env bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wait-lib.sh"   # bounded condition waits (iq02 T07)
# test-automate-lanes.sh — hermetic self-tests for automate-lanes.sh (parallel-automate/05, lane
# lifecycle). Fixture: a bare fake origin + a "primary" clone of it holding two items and a parent run
# file, all under one mktemp dir. `claude` is a PATH stub that records argv / env / stdin and prints
# stream-json; `gh` is a PATH stub that fails the test if called; meta-sync / setup-memory /
# automate-helpers / machine-load are stubbed through the script's seams. No network, no real claude.
#
# Groups: A create (AC1) · B leftover salvage · C meta pull failure · D hook merge · E init-check (AC12)
#   F launch authority / regime / host denial · G admission (AC10 launch-hold half) · H launch shape
#   I checksum + mutation control (AC16) · J relay hook (AC6) · K lane-answer (AC6) · L .died marker
#   M liveness + pick-guard (AC12) · N lane-remove refusals (AC3) + mutation controls (AC16)
#   O lane-info · P branch-check · Q lane-status classification (AC7) · R lane-status --json (AC8)
#   S keep-awake · T --watch + lane-feed · U merge-readiness (AC9) · V --leaks / --resources / --tokens
#     (V15-V20: the merge-watch section reads live watchers from their markers — a process that only NAMES
#     the script is no leak, + mutation control; a v1 snapshot section is not compared)
#   W drain-round-1 hardening: one-call token total (D8) + mutation control · trailing value flags
#     exit promptly · unpushed count unreadable refuses + mutation control · lock holder records
#     (dead holder reclaimed, live holder waited on, foreign lock never unlocked, holder-less lock
#     reclaimed) · two concurrent launches spawn once · multiSelect labels containing commas ·
#     lane-remove --stop refuses before stopping + mutation control
#   X relay hook from a linked worktree of the lane (git common dir; older git) + mutation control
#   Y lane-convert-ready: refusals, convert + single-path push, idempotent re-run, failed push, removal
#   Z Validation 4/5 fixes (parallel-automate/23): F5 readiness report · F9 leak check after removal ·
#     F1 snapshot before the lane table · F10 no absolute path / real state · F4 resume in the last
#     session · F2 HELD answer kept + delivered under an owner command · F11 gated wave-end push + ABANDONED
#   AA Validation 4/5 fixes B (parallel-automate/24): F6 lane-park-notify (truthful per-channel delivery)
#     · F8 real transcript usage ⇒ non-zero lane TOTAL + a ceiling-check PARK · F12 lane-feed --follow leaves
#     no pipeline behind on TERM / HUP / INT, and no process naming the suite dir outlives the suite
#   AB merged lane close-out (automate-followups/38): lane-convert-ready runs `closeout --no-trail` inside
#     the lane on its awaiting_merge re-run only (OPEN ⇒ nothing written; MERGED ⇒ stamp + check-off +
#     done/awaiting_go, pushed), a done/awaiting_go re-run retries only the pushes, leftover / no-pr / mode off
#   AC a lane whose run wrote an Orchestrator task plan: the wave-end exact list carries it (a done-headed
#     *-plan.md never), the re-run names the state it reads, lane-remove removes with no hand push + mutation
#     (parallel-automate/21 A1: in branch mode the merged re-run also finalizes, so AB3f/AB3g/AB4b read the
#     finalized state — `pause_reason: null`, `## Status: done`; the done/awaiting_go re-run is AE4c)
#   AD fleet operations Part B (parallel-automate/21): lane-create carries the resolved policy into lane.json
#     (null without one), relay-hook applies a policy answer (source policy) or defers exactly as before,
#     lane-status policy digest + --inbox
#   AE lane-convert-ready finalizes a closed-out lane in branch mode (A1); mode off skips finalize
#   AF fleet-closeout: stepwise, idempotent wave close (A2) — backstop, check-off, sync, removal, lanes dir,
#     leaks, main health, lock release; gone / meta-push-failed are the human's; a failed pull stops it;
#     AF3m-AF12 the Queue-empty parent finalize (done + wave line cleared + one trail-pr, skipped on a
#     re-run, never with an item left, FAILED write still releases the lock, mode off unstages) + mutation
#   AH lane-wait: the coordinator's lane watcher — events, seen ledger (prune / keep), timeout, idle,
#     usage, read-only toward lanes; AH15 its liveness marker (written, handed over to a second watcher,
#     removed only by its owner, absent on the idle paths); AH16 _lanes_quick_state (the Stop hook's
#     classifier) agrees with lane-status on every live / attention state of the fleet
#   AI gate opt-out carry (lane-guardrails part 3): the FACT recorded coordinator-side at first launch,
#     every resume path refused without it (exit 3, no spawn, nothing in the lane), lane-answer keeps the
#     validated answer pending, --without-gate-optout resumes without it and clears the fact, never added
#   AG wave-plan is READ-ONLY (A4: refs + tree byte-identical) + mutation control; the A3/A4 static guards
#     (no executable merge / push / gate-eval) + mutation control; A5 no sequential caller
#   AK a lane whose worker filed a proposed/ requirement draft (wave W4): the wave-end exact list carries
#     it (a done-headed proposed/ file never), the lane is removable with no hand push; lane-remove's
#     unpushed-metadata refusal — and so fleet-closeout's waiting line — names the paths + two mutations
#   AJ lane timeline: the seven steps from `## Progress` + Supervisor state (pick-guarded), boundaries,
#     current-step state per lane state, a park before the drain stays on the step reached (L5 Launch Pad
#     blocked, unpinned wordings, the pinned no-PR status_reason line) + mutation controls, the JSON fields
#     and the plain steps line; `waves` from the
#     parent run file's wave-build records (undated hand line, colon inside the parenthetical)
#   E7-E9 init-check single-lane mode: branch mode required for N = 1 (fail CLOSED), no mode read for N > 1
#   SL single-lane mode `--parallel 1` (twin-remediation/08b): lane.json single_lane (first leg) · lane-park seam ·
#     fresh lane numbers 1..99 · whole-run token ceiling · lane-remove / fleet-closeout `fleet closeout: <lane>
#     tokens TOTAL=<n>` line (before the removal) · lane-drain-check (dispatch marker by the dispatcher's own
#     PR_HASH block, owned drains after the LAST picked — timestamp optional, colon form tolerated — config
#     backup, unknown) · both tokens-line readers take an optional timestamp · current-set's single_lane
#     refusal · the merge watcher's documented launch line outlives its parent + a nohup mutation control
#   AL validation-gate (af36-remainder/01): the #402 replay (pa/16's bullet Validation + PR #402's body,
#     both fixtures under fixtures/validation-gate/) ⇒ unrun; evidenced ⇒ ok; no running-system step ⇒
#     none; unreadable PR body / item ⇒ unrun; "Not verified" heading ⇒ NOT-RUN; FAIL ⇒ unrun; the owner
#     waiver (counted only for its item, after the last `picked <item>`) + its refusals; a `|`-bearing title is a legal
#     `current-escalation --check`; ONE shared reader; AC9 mutation control (unconditional ok ⇒ AL1 red);
#     fence-aware PR-body + item scans, a "running system" title outranking the repro rule, and evidence
#     attributed to the step (not-run line, bold pseudo-heading, sibling bullet, next paragraph) — AL11–AL16;
#     a not-run statement on any non-fenced line, an anchored step's intro paragraph, and no title-keyed
#     evidence for a title two entries share — AL17–AL19, U13c; an anchored passage crossing a paragraph
#     break only via an intro line ending in `:`, the wider not-run vocabulary — AL20–AL20g; a waiver
#     bound to its item (named in the line, refused for any item but the last picked) — AL7h–AL7m;
#     `* ` / `+ ` / `N) ` entries parse like `- ` / `N. `, a section that exists but parses to no entry
#     reads `unrun` (never `none`) with its own mutation control, and the not-run vocabulary matches
#     whole phrases only ("not running hot" stays PASS) — AL22–AL22h
#   AM superseded lane questions (L8, 2026-10-16): the lane abandons toolu_s1, re-asks toolu_s2 ⇒ s1 moves to
#     questions/superseded/ naming s2 + one lane ## Progress line, lane-answer / --deliver-pending refuse s1 by
#     name, the resume re-fire of s2 supersedes nothing, 0 pending and the lane reads its park + mutation control
#   AN phase sessions (automate-speed/09, fresh session per phase): phase-check ok / unavailable + mutation;
#     phase-launch BLOCKED without an owner command (no process) + mutation; the launch shape (lane flag list
#     + --settings relay hook only, cwd = checkout, LOOMWRIGHT_PHASE_DIR / LOOMWRIGHT_RUN_LOCK_SESSION_ID set,
#     holder pin unset); a phase question inside a LANE clone lands in the phase dir, never the lane inbox
#     (+ mutation: phase branch deleted ⇒ `{}` and no file); phase-wait question (5) → phase-answer
#     refusals + BLOCKED → resume of the SAME session → done (0); running (3) / died (6); a lane spawn
#     strips both phase variables + one mutation each
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/automate-lanes.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
BG_PIDS=""
# ere <text> — <text> as a literal extended regex (pgrep / pkill -f take an ERE: an unescaped `+` in
# `tail -n +1` means "one or more spaces", so the literal never matched — parallel-automate/24 F12).
ere() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }
cleanup() {
  local p
  for p in $BG_PIDS $(pgrep -f "_lane-run $T" 2>/dev/null); do kill -TERM "$p" 2>/dev/null; done
  pkill -TERM -f "$(ere "$T")" 2>/dev/null   # safety net only — the AA-F12z leg is the assertion
  rm -rf "$T"
}
trap cleanup EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing [$3] in [$(printf '%s' "$2" | head -c 600)]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected [$3]" ;; *) ok "$1" ;; esac; }
# SB — the entry point's own _lanes_bundle expansion of automate-lanes.sh (its automate-lanes.d/ modules
# inlined at their source points: the single file this suite was written against), built ONCE. Every TEXT
# read of the script — each mutant builder (`awk/sed/grep -v … "$SB" > …`), its `cmp -s` gate and the
# static greps — reads $SB; every RUN still runs the real entry point "$S" (a mutant written from $SB is
# one self-contained file, so it runs without a .d dir). Fails the whole suite if it cannot be built.
SB="$T/automate-lanes.bundle.sh"
eval "$(awk '/^_lanes_bundle\(\) \{$/,/^}$/' "$S")"
_lanes_bundle "$S" > "$SB" && [ -s "$SB" ] || { echo "FAIL - could not build the automate-lanes.sh bundle"; exit 1; }

export HOME="$T/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_PLUGIN_ROOT LOOMWRIGHT_ROOT LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS   # the AI group sets the opt-out per command; a pre-set neutral root would beat the location-derived one

BIN="$T/bin"; mkdir -p "$BIN"
export STUB_LOG="$T/claude.log"; : > "$STUB_LOG"
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  if [ -n "${STUB_NO_REGIME:-}" ]; then echo "Usage: claude [options]"; else echo "--permission-prompt-tool --allowedTools --disallowedTools --plugin-dir"; fi
  exit 0
fi
{ printf 'ARGS'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  printf 'ENV CEIL=%s CC=%s PID=%s OPTOUT=%s\n' "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS-unset}" "${CLAUDECODE-unset}" "${CLAUDE_PID-unset}" "${LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS-unset}"
  printf 'HOLDERENV %s\n' "${LOOMWRIGHT_HOLDER_PID-unset}"
  printf 'STDIN %s\n' "$(cat)"; printf 'CWD %s\n' "$PWD"
  printf 'RESUMEPATH %s\n' "${LOOMWRIGHT_LANE_RESUME_PATH-unset}"
  printf 'PHASEENV dir=%s lock=%s\n' "${LOOMWRIGHT_PHASE_DIR-unset}" "${LOOMWRIGHT_RUN_LOCK_SESSION_ID-unset}"; } >> "$STUB_LOG"
# STUB_HOOK_INPUT (AN group): stand in for the CLI firing the PreToolUse hook that `--settings` carries —
# run its command with that hook JSON on stdin, in this process's environment, and log its reply.
if [ -n "${STUB_HOOK_INPUT:-}" ]; then
  prev=""; st=""; for a in "$@"; do [ "$prev" = --settings ] && st="$a"; prev="$a"; done
  hc="$(printf '%s' "$st" | jq -r '.hooks.PreToolUse[0].hooks[0].command // empty' 2>/dev/null)"
  printf 'HOOKOUT %s\n' "$( [ -n "$hc" ] && printf '%s' "$STUB_HOOK_INPUT" | bash -c "$hc" 2>&1)" >> "$STUB_LOG"
fi
if [ -n "${STUB_RESUME_FAIL:-}" ]; then
  for a in "$@"; do [ "$a" = --resume ] && { echo "No conversation found with session ID" >&2; exit 1; }; done
fi
echo '{"type":"system","subtype":"init","session_id":"sess-123"}'
case "${STUB_MODE:-ok}" in
  sleep) trap 'kill $! 2>/dev/null; exit 143' TERM; sleep 60 & wait $! ;;
  defer) printf '%s\n' "$STUB_DEFER_LINE" ;;
  die) exit 1 ;;
  *) echo '{"type":"result","subtype":"success","stop_reason":"end_turn","session_id":"sess-123"}' ;;
esac
EOF
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "${GH_CALLS:-/dev/null}"; exit 1
EOF
export GH_CALLS="$T/gh.calls"
cat > "$T/meta-sync.sh" <<'EOF'
#!/usr/bin/env bash
echo "meta-sync $*" >> "$META_LOG"
case "$1" in
  pull) [ -n "${STUB_META_FAIL:-}" ] && exit 1; exit 0 ;;
  status) echo "${STUB_META_STATUS:-in_sync}"; exit 0 ;;
esac
EOF
cat > "$T/setup-memory.sh" <<'EOF'
#!/usr/bin/env bash
echo "${STUB_MODE_LINE:-on test-meta}"
EOF
cat > "$T/helpers.sh" <<'EOF'
#!/usr/bin/env bash
echo "helpers $*" >> "$HELPERS_LOG"
EOF
cat > "$T/load.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"load1":1,"cpus":8,"state":"%s"}\n' "${STUB_LOAD:-ok}"
EOF
chmod +x "$BIN/claude" "$BIN/gh" "$T"/*.sh
export PATH="$BIN:$PATH"
export META_LOG="$T/meta.log" HELPERS_LOG="$T/helpers.log"; : > "$META_LOG"; : > "$HELPERS_LOG"
export LOOMWRIGHT_LANES_META_SYNC="$T/meta-sync.sh" LOOMWRIGHT_LANES_SETUP_MEMORY="$T/setup-memory.sh"
export LOOMWRIGHT_LANES_HELPERS="$T/helpers.sh" LOOMWRIGHT_MACHINE_LOAD_CMD="$T/load.sh"
export LOOMWRIGHT_LANES_INIT_WAIT_S=5 LOOMWRIGHT_LANES_STOP_GRACE_S=2
# the wave-end evidence-gated trail (F11) runs through this seam; a no-op stub everywhere but Z-F11
cat > "$T/trail-stub.sh" <<'EOF'
#!/usr/bin/env bash
echo "trail $*" >> "$T_TRAIL_LOG"; echo "trail-pr: skipped — meta no_changes"
EOF
chmod +x "$T/trail-stub.sh"; export LOOMWRIGHT_LANES_TRAIL="$T/trail-stub.sh" T_TRAIL_LOG="$T/trail.log"

# ---- fixture ----------------------------------------------------------------------------------------
ORIGIN="$T/origin.git"; P="$T/work/primary"
git init -q --bare "$ORIGIN"; git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
git init -q "$P"; git -C "$P" checkout -q -b main
printf '.supervisor/*\n.claude/settings.local.json\n' > "$P/.gitignore"
mkdir -p "$P/reqs"; echo "# a" > "$P/reqs/a.md"; echo "# b" > "$P/reqs/b.md"
git -C "$P" add -A; git -C "$P" commit -qm init
git -C "$P" remote add origin "$ORIGIN"; git -C "$P" push -q -u origin main 2>/dev/null
git -C "$P" branch primary-only
PARENT=automate-2026-10-07-120000
mkdir -p "$P/.supervisor/automate"
printf '# Automate Run: %s\n\n## Progress\n' "$PARENT" > "$P/.supervisor/automate/$PARENT.md"
printf '{"auto_review": true, "x": [1, 2]}\n' > "$P/.supervisor/config.json"
printf '{"desktop": false}\n' > "$P/.supervisor/notify-config.json"
RF="$P/.supervisor/automate/$PARENT.md"; TABLE="$P/.supervisor/automate/$PARENT.lanes"
LR="$T/work/primary-lanes/$PARENT"
run() { bash "$S" "$@" 2>&1; }
claude_calls() { grep -c '^ARGS' "$STUB_LOG" | tr -d ' '; }
tcol() { awk -F'\t' -v l="$1" -v c="$2" '$1 == l { print $c }' "$TABLE"; }
lane_sum() { (cd "$1" && find . -path ./.git -prune -o -type f -print | env LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done) | cksum; }
wait_gone() { local i=0; while pgrep -f "_lane-run $1 " >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }

# ---- test parts (automate-speed/19) --------------------------------------------------------------------
# Every test leg (groups A … AL, then the closing Z1 / AA-F12z legs) lives in test-automate-lanes.d/<part>.sh,
# moved verbatim and in order. Each part is sourced here at TOP LEVEL (never inside a function: every
# variable, helper and `$?` flows from one part into the next exactly as in one file), by name — never a
# glob. A missing or unreadable part is a FAIL, never a silently shorter run.
tal_part() { [ -r "$HERE/test-automate-lanes.d/$1.sh" ] || { bad "test part missing or unreadable: test-automate-lanes.d/$1.sh"; return 1; }; }
tal_part 01-create-to-wait && . "$HERE/test-automate-lanes.d/01-create-to-wait.sh"
tal_part 02-readiness-to-convert && . "$HERE/test-automate-lanes.d/02-readiness-to-convert.sh"
tal_part 03-fixes-to-finalize && . "$HERE/test-automate-lanes.d/03-fixes-to-finalize.sh"
tal_part 04-fleet-closeout-to-optout && . "$HERE/test-automate-lanes.d/04-fleet-closeout-to-optout.sh"
tal_part 05-timeline-and-gate && . "$HERE/test-automate-lanes.d/05-timeline-and-gate.sh"
tal_part 06-phase-sessions && . "$HERE/test-automate-lanes.d/06-phase-sessions.sh"
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
