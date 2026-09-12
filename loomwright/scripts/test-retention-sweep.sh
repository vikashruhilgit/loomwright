#!/usr/bin/env bash
# test-retention-sweep.sh — self-tests for retention-sweep.sh, the `.supervisor/`
# retention policy and its report-by-default sweep.
#
# EVERY invocation runs against a fixture `.supervisor/` built under this suite's
# own `mktemp -d`, and EVERY invocation passes `--project-root <fixture>`
# explicitly — never a cwd-resolved root. The tool is irreversible against the
# one place that data exists, so the suite refuses to start if its temp root is
# itself inside a git repository (that would also make the non-git rc-128 arm
# vacuous: git would answer for the parent repo). Ubuntu-clean AND macOS
# bash 3.2 / BSD-clean: `touch -t` for aging, `cksum` for hashes, no `timeout`,
# no `mapfile`, no `sed -i`. Auto-included by ci.yml's `test-*.sh` glob.
#
# Groups (AC numbers are the job brief's):
#   AC-3   report-only default: the full recursive listing (files AND dirs, a
#          cksum per file) is byte-identical before/after — asserted against the
#          filesystem, never against the tool's own claim
#   AC-11  argument hygiene (0 / 08 / abc / missing value / above 36500 ⇒ REPORT
#          + reason, nothing removed; 36500 itself accepted) and the
#          IRREVERSIBLE line FIRST in both modes
#   AC-1   the five tracked files survive --delete --older-than 1, each hash
#          asserted individually
#   AC-2   aged review-dispatch/ and postmortem-dispatch/ markers survive
#   AC-4   --delete removes the aged consumed log, the aged postmortem-dispatch
#          transcript and the aged ledgers; the aged review-drain transcript
#          (build-insights.sh's opt-out evidence) survives; every non-exhaust
#          class keeps its file count — both halves. Transcript prefixes are
#          DERIVED from the producers' `RUN_LOG=` lines so a renamed producer
#          turns this red rather than leaving a silently no-op glob
#   AC-5   curation-status.sh status --json reports identical dreaming.pending
#          and insights.pending before/after, on a fixture holding aged
#          UNCONSUMED signal logs — two arms: cwd == root, and cwd == a second,
#          differently-populated fixture with --project-root naming the first
#          (the second fixture's listing must be byte-identical afterwards)
#   AC-1b  an aged, committed, TRACKED file inside drain-rounds/ survives
#   AC-1c  a candidate that becomes tracked BETWEEN the listing pass and the
#          deletion pass survives — injected with a `git` shim on PATH that
#          stages the file for real on its first ls-files probe and answers
#          "not tracked" that once; the report lists it as would-remove, the
#          deletion pass names it `keep (tracked at deletion time)`
#   AC-1d  the same shim answers rc 128 at deletion time ⇒ that file is kept
#          (`keep (git could not answer at deletion time, rc 128)`), its
#          siblings still removed, the summary counting actual removals
#   AC-1e  the shim renames the candidate away on its first probe ⇒ pass 2
#          prints `skipped (not a regular file now)` and the moved file is
#          untouched; AC-1f replaces it with a symlink ⇒ the same skip line,
#          the link and its target untouched. (A former `skipped (no longer
#          matches <glob>)` arm was REMOVED: the candidate TSV row is
#          name-safe by construction — pass 1 refuses tab/newline names, see
#          AC-1g — so the arm was redundant.)
#   AC-1g  a TAB in a candidate's basename would split the TSV row and make
#          pass 2 act on the pre-tab prefix; pass 1 refuses it — `keep (unsafe
#          name, not swept)`, the tab-named file AND its same-prefix untracked
#          sibling survive, the summary excludes it. Gated mutant (a5) removes
#          the guard ⇒ the sibling is deleted (RED as required)
#   AC-6   a novel directory (zzz-future/) keeps its aged file and is reported
#          `unclassified — not swept`
#   AC-7   fail-safe, one assertion per case: unreadable dir (both exhaust dirs
#          ⇒ nothing deleted; one exhaust dir ⇒ never widens), garbage
#          curation-state.json, PATH without jq, PATH without git, non-git
#          --project-root (rc 128) — exit 0, nothing deleted, condition named
#   AC-8   hooks/hooks.json carries no retention-sweep reference
#   AC-9   mutation controls, each a copy of the script with ONE identifiable
#          edit, asserted RED: (a1) memory/ + postmortem/ reclassified exhaust;
#          (a2) BOTH ls-files guard lines removed (listing-time and
#          deletion-time) — with only the listing-time line removed the
#          deletion-time re-check still keeps the tracked file (asserted
#          green, the layering of guard ii across the two passes); (a3) only
#          the deletion-time line removed lets the AC-1c becomes-tracked file
#          fall; (a1+a2) rows + both lines — the only way the five tracked
#          files can fall, which is the layering claim itself; (a4) the
#          deletion-time could-not-answer arm deleted so rc 128 falls through
#          to rm ⇒ AC-1d red; (a5) the unsafe-name guard removed ⇒ AC-1g's
#          same-prefix sibling is deleted; (b) the two guard rows reclassified exhaust;
#          (c) the pending-ids exclusion line removed
#   AC-10  policy mirror: `retention-sweep.sh policy` and the
#          ARCHITECTURE_CONTRACTS.md retention table name the same directory set
#          with the same classes, both directions

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RS="$SCRIPT_DIR/retention-sweep.sh"
CS="$SCRIPT_DIR/curation-status.sh"
HOOKS="$PLUGIN_ROOT/hooks/hooks.json"
CONTRACTS="$PLUGIN_ROOT/docs/ARCHITECTURE_CONTRACTS.md"

pass=0; fail=0; skip=0
ok()  { echo "  ok: $1"; pass=$((pass+1)); }
no()  { echo "  FAIL: $1"; fail=$((fail+1)); }
skp() { echo "  SKIP: $1"; skip=$((skip+1)); }

for t in jq git; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "test-retention-sweep: $t absent on this host — the tool degrades to REPORT; assertions would be vacuous."
    echo "RESULT: 0 passed, 0 failed ($t absent, vacuous)"
    exit 0
  fi
done

ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$ROOT" 2>/dev/null; rm -rf "$ROOT" 2>/dev/null' EXIT
if git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "test-retention-sweep: the temp root $ROOT is INSIDE a git repository — refusing to run (the non-git arm would be vacuous and a fixture could be mistaken for real state)."
  exit 1
fi
TAB="$(printf '\t')"
OLD=202601010000          # the aged stamp: > 90 days before any run date of this suite's life
DASH=202603010000         # the /insights watermark (dashboard.md mtime)
MID=202604010000          # aged relative to now, but NEWER than the watermark

# Transcript prefixes DERIVED from the producers (prefix up to `$TIMESTAMP`).
derive_prefix() { grep -m1 'RUN_LOG=' "$1" | sed -E 's/.*LOG_DIR\/([^$]*)\$TIMESTAMP.*/\1/'; }
PM_PREFIX="$(derive_prefix "$SCRIPT_DIR/dispatch-pr-postmortem.sh")"
RV_PREFIX="$(derive_prefix "$SCRIPT_DIR/dispatch-pr-review.sh")"
if [ -z "$PM_PREFIX" ] || [ -z "$RV_PREFIX" ] || [ "$PM_PREFIX" = "$RV_PREFIX" ]; then
  echo "  FAIL: could not derive the two transcript prefixes from the producers (pm='$PM_PREFIX' rv='$RV_PREFIX')"
  echo "RESULT: 0 passed, 1 failed"; exit 1
fi
ok "setup — transcript prefixes derived from producers: '$PM_PREFIX' / '$RV_PREFIX'"

TRACKED="memory/LESSONS.md memory/PROJECT_MEMORY.md memory/.lessons-provenance.jsonl memory/.provenance.jsonl postmortem/results.jsonl"
NONEXHAUST_DIRS="memory postmortem review-dispatch postmortem-dispatch history worker-summaries scratch jobs insights zzz-future"

# build_fixture <dir> [tracked-in-drain-rounds] — a git repo with a populated
# .supervisor/. The five tracked files are committed AND THEN aged: a
# just-committed file is skipped by `-mtime +1` even with every guard removed,
# which would make AC-1 and its mutant vacuous.
build_fixture() {
  local r="$1" extra="${2:-}" s="$1/.supervisor"
  mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
  printf '.supervisor/*\n!.supervisor/memory/\n!.supervisor/postmortem/\n.supervisor/postmortem/*\n!.supervisor/postmortem/results.jsonl\n' > "$r/.gitignore"
  mkdir -p "$s/memory" "$s/postmortem"
  local t
  for t in $TRACKED; do printf 'tracked %s\n' "$t" > "$s/$t"; done
  if [ "$extra" = "tracked-in-drain-rounds" ]; then
    mkdir -p "$s/drain-rounds"
    printf '{"rounds":0,"max_rounds":5,"tracked":true}\n' > "$s/drain-rounds/tracked.json"
    ( cd "$r" && git add -f .supervisor/drain-rounds/tracked.json ) >/dev/null 2>&1
  fi
  ( cd "$r" && git add -A && git commit -qm fixture ) >/dev/null 2>&1
  for t in $TRACKED; do touch -t "$OLD" "$s/$t"; done
  [ "$extra" = "tracked-in-drain-rounds" ] && touch -t "$OLD" "$s/drain-rounds/tracked.json"

  mkdir -p "$s/logs" "$s/drain-rounds" "$s/review-dispatch" "$s/postmortem-dispatch" \
           "$s/zzz-future" "$s/history" "$s/worker-summaries" "$s/scratch" "$s/jobs/done" "$s/insights"
  # session logs
  printf '{"event":"session_end","id":"old-consumed"}\n'  > "$s/logs/old-consumed.jsonl"
  printf '{"event":"session_end","id":"old-unconsumed"}\n' > "$s/logs/old-unconsumed.jsonl"
  printf '{"event":"session_end","id":"mid-consumed"}\n'  > "$s/logs/mid-consumed.jsonl"   # insights-pending (newer than dashboard)
  printf '{"event":"token_ledger"}\n{"event":"subtask_complete"}\n' > "$s/logs/old-noise.jsonl"  # no signal for either consumer
  printf '{"event":"session_end","id":"new"}\n'           > "$s/logs/new.jsonl"
  touch -t "$OLD" "$s/logs/old-consumed.jsonl" "$s/logs/old-unconsumed.jsonl" "$s/logs/old-noise.jsonl"
  touch -t "$MID" "$s/logs/mid-consumed.jsonl"
  printf '{"dreaming":{"last_run":"2026-05-01T00:00:00Z","consumed":{"logs":["old-consumed","mid-consumed","old-noise"]}}}' > "$s/curation-state.json"
  printf '# dashboard\n' > "$s/insights/dashboard.md"; touch -t "$DASH" "$s/insights/dashboard.md"
  # non-event files in logs/
  printf 'pm transcript\n' > "$s/logs/${PM_PREFIX}20260101T000000Z-abc.log"
  printf 'rv transcript\n' > "$s/logs/${RV_PREFIX}20260101T000000Z-abc.log"
  printf 'f\n' > "$s/logs/failures.log"; printf 'o\n' > "$s/logs/run-1.owner"; printf 'w\n' > "$s/logs/worktrees.log"
  touch -t "$OLD" "$s/logs/${PM_PREFIX}"* "$s/logs/${RV_PREFIX}"* "$s/logs/failures.log" "$s/logs/run-1.owner" "$s/logs/worktrees.log"
  # ledgers
  printf '{"rounds":0,"max_rounds":5}\n' > "$s/drain-rounds/aaa.json"
  printf '{"rounds":1,"max_rounds":5}\n' > "$s/drain-rounds/bbb.json"
  printf '{"rounds":0,"max_rounds":5}\n' > "$s/drain-rounds/ccc-new.json"
  touch -t "$OLD" "$s/drain-rounds/aaa.json" "$s/drain-rounds/bbb.json"
  # guards, novel dir, other consumed classes, top-level
  printf 'm\n' > "$s/review-dispatch/deadbeef"; printf 'm\n' > "$s/postmortem-dispatch/deadbeef"
  printf 'z\n' > "$s/zzz-future/aged"
  printf 'h\n' > "$s/history/2026-01-01-state.md"; printf 'w\n' > "$s/worker-summaries/BD-1.md"
  printf 's\n' > "$s/scratch/spike.txt"; printf 'j\n' > "$s/jobs/done/2026-01-01-x.md"
  printf '{}\n' > "$s/config.json"; printf '# state\n' > "$s/state.md"; printf 'x\n' > "$s/.current-session"
  touch -t "$OLD" "$s/review-dispatch/deadbeef" "$s/postmortem-dispatch/deadbeef" "$s/zzz-future/aged" \
       "$s/history/2026-01-01-state.md" "$s/worker-summaries/BD-1.md" "$s/scratch/spike.txt" \
       "$s/jobs/done/2026-01-01-x.md" "$s/config.json" "$s/state.md" "$s/.current-session"
}

# listing <root> — full recursive listing of .supervisor/ (files AND dirs, a
# cksum per regular file), sorted. A bare name list would miss an rmdir or a
# truncation.
listing() {
  ( cd "$1" && find .supervisor \( -type f -o -type d \) -print 2>/dev/null | LC_ALL=C sort | while IFS= read -r p; do
      if [ -f "$p" ] && [ ! -L "$p" ]; then printf '%s %s\n' "$p" "$(cksum < "$p" | cut -d' ' -f1,2)"; else printf '%s\n' "$p"; fi
    done )
}
hash_of() { cksum < "$1" 2>/dev/null | cut -d' ' -f1,2; }
count_in() { find "$1" -type f 2>/dev/null | wc -l | tr -d ' '; }

# run_rs <tool> <cwd> <root> <args...> — stdout+stderr in OUT, exit in RC.
# ALWAYS passes --project-root explicitly.
run_rs() {
  local tool="$1" cwd="$2" root="$3"; shift 3
  OUT="$(cd "$cwd" && bash "$tool" --project-root "$root" "$@" 2>&1)"; RC=$?
}
pending_pair() {  # <root> — "dreaming insights" pending numbers from status --json
  ( cd "$1" && LOOMWRIGHT_CURATION_REMOTE=0 bash "$CS" status --json 2>/dev/null ) \
    | jq -r '[.commands.dreaming.pending, .commands.insights.pending] | map(tostring) | join(" ")' 2>/dev/null
}

# ============================================================================
echo "== AC-3 / AC-11: report-only default, argument hygiene, IRREVERSIBLE first =="
F3="$ROOT/f3"; build_fixture "$F3"
before="$(listing "$F3")"
run_rs "$RS" "$F3" "$F3"
[ "$RC" -eq 0 ] && ok "AC-3 default invocation exits 0" || no "AC-3 rc=$RC"
printf '%s' "$OUT" | grep -qF 'would remove:' && ok "AC-3 control — the default report DOES list candidates (the fixture is aged past 90 days)" || no "AC-3 control: no candidates listed — the report-only assertion would be vacuous: $OUT"
[ "$(listing "$F3")" = "$before" ] && ok "AC-3 default invocation leaves the full listing byte-identical" || no "AC-3 listing changed under the default invocation"
printf '%s' "$OUT" | grep -qF 'pass --delete to remove the files listed above' && ok "AC-3 summary says nothing removed / pass --delete" || no "AC-3 summary line missing: $(printf '%s' "$OUT" | tail -1)"
[ "$(printf '%s\n' "$OUT" | head -1)" = 'retention-sweep: IRREVERSIBLE — .supervisor/ is gitignored and exists only in this checkout; nothing removed here can be recovered.' ] \
  && ok "AC-11 REPORT mode: the IRREVERSIBLE line is the FIRST line" || no "AC-11 REPORT first line: $(printf '%s\n' "$OUT" | head -1)"

for bad in 0 08 abc; do
  run_rs "$RS" "$F3" "$F3" --delete --older-than "$bad"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "mode=REPORT" && printf '%s' "$OUT" | grep -qF -- "--older-than '$bad'" && [ "$(listing "$F3")" = "$before" ]; then
    ok "AC-11 --older-than $bad with --delete ⇒ exit 0, REPORT, reason names the value, nothing removed"
  else
    no "AC-11 --older-than $bad: rc=$RC / $(printf '%s\n' "$OUT" | sed -n 2,3p)"
  fi
done
run_rs "$RS" "$F3" "$F3" --delete --older-than
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "mode=REPORT" && printf '%s' "$OUT" | grep -qF -- "--older-than needs a value" && [ "$(listing "$F3")" = "$before" ]; then
  ok "AC-11 --older-than with a missing value ⇒ exit 0, REPORT, reason, nothing removed"
else
  no "AC-11 missing value: rc=$RC / $(printf '%s\n' "$OUT" | sed -n 2,3p)"
fi
run_rs "$RS" "$F3" "$F3" --older-than 30
printf '%s' "$OUT" | grep -qF 'older-than=30 days' && ok "AC-11 a valid --older-than is honoured (30)" || no "AC-11 valid value not honoured: $(printf '%s\n' "$OUT" | sed -n 2p)"
# Upper bound: above 36500 `find -mtime +N` silently yields nothing — a run that looks clean and did nothing.
for big in 36501 999999999999 99999999999999999999999; do
  run_rs "$RS" "$F3" "$F3" --delete --older-than "$big"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -qF "mode=REPORT" && printf '%s' "$OUT" | grep -qF -- "--older-than '$big' is rejected (above 36500 days" && printf '%s' "$OUT" | grep -qF "older-than=90 days" && [ "$(listing "$F3")" = "$before" ]; then
    ok "AC-11 --older-than $big with --delete ⇒ exit 0, REPORT, reason names the bound, threshold stays 90, nothing removed"
  else
    no "AC-11 --older-than $big: rc=$RC / $(printf '%s\n' "$OUT" | sed -n 2,3p)"
  fi
done
run_rs "$RS" "$F3" "$F3" --older-than 36500
printf '%s' "$OUT" | grep -qF 'older-than=36500 days' && printf '%s' "$OUT" | grep -qF 'mode=REPORT' && ! printf '%s' "$OUT" | grep -qF 'is rejected' \
  && ok "AC-11 --older-than 36500 (the bound itself) is accepted" || no "AC-11 36500 not accepted: $(printf '%s\n' "$OUT" | sed -n 2,3p)"

# ============================================================================
echo "== AC-1 / AC-2 / AC-4 / AC-5 / AC-6: --delete --older-than 1 on the aged fixture (cwd == root) =="
F4="$ROOT/f4"; build_fixture "$F4"; S4="$F4/.supervisor"
declare_hashes() { local t; for t in $TRACKED; do printf '%s=%s\n' "$t" "$(hash_of "$1/.supervisor/$t")"; done; }
h_before="$(declare_hashes "$F4")"
pp_before="$(pending_pair "$F4")"
[ "$pp_before" = "2 2" ] && ok "AC-5 control — before: dreaming.pending=2 (old-unconsumed, new) insights.pending=2 (mid-consumed, new)" || no "AC-5 control: expected '2 2', got '$pp_before'"
counts_before=""; for d in $NONEXHAUST_DIRS; do counts_before="$counts_before $d=$(count_in "$S4/$d")"; done
run_rs "$RS" "$F4" "$F4" --delete --older-than 1
[ "$RC" -eq 0 ] && ok "--delete exits 0" || no "--delete rc=$RC"
[ "$(printf '%s\n' "$OUT" | head -1)" = 'retention-sweep: IRREVERSIBLE — .supervisor/ is gitignored and exists only in this checkout; nothing removed here can be recovered.' ] \
  && ok "AC-11 DELETE mode: the IRREVERSIBLE line is the FIRST line" || no "AC-11 DELETE first line: $(printf '%s\n' "$OUT" | head -1)"
printf '%s' "$OUT" | grep -qF 'mode=DELETE' && ok "AC-4 mode=DELETE was actually entered (not silently degraded)" || no "AC-4 mode line: $(printf '%s\n' "$OUT" | sed -n 2,4p)"
# AC-1, individually
for t in $TRACKED; do
  if [ -f "$S4/$t" ] && [ "$(hash_of "$S4/$t")" = "$(printf '%s\n' "$h_before" | grep -F "$t=" | cut -d= -f2)" ]; then
    ok "AC-1 tracked $t present with unchanged hash"
  else
    no "AC-1 tracked $t missing or changed"
  fi
done
# AC-2
[ -f "$S4/review-dispatch/deadbeef" ] && ok "AC-2 aged review-dispatch/ marker survives" || no "AC-2 review-dispatch marker removed"
[ -f "$S4/postmortem-dispatch/deadbeef" ] && ok "AC-2 aged postmortem-dispatch/ marker survives" || no "AC-2 postmortem-dispatch marker removed"
# AC-4 removed half
[ ! -e "$S4/logs/old-consumed.jsonl" ] && ok "AC-4 aged CONSUMED session log removed" || no "AC-4 old-consumed.jsonl still present"
[ ! -e "$S4/logs/old-noise.jsonl" ] && ok "AC-4 aged signal-less (noise-only) log removed" || no "AC-4 old-noise.jsonl still present"
[ ! -e "$S4/logs/${PM_PREFIX}20260101T000000Z-abc.log" ] && ok "AC-4 aged ${PM_PREFIX}* transcript removed" || no "AC-4 postmortem transcript still present"
[ ! -e "$S4/drain-rounds/aaa.json" ] && [ ! -e "$S4/drain-rounds/bbb.json" ] && ok "AC-4 aged drain ledgers removed" || no "AC-4 aged ledgers still present"
# AC-4 kept half
[ -f "$S4/logs/${RV_PREFIX}20260101T000000Z-abc.log" ] && ok "AC-4 aged ${RV_PREFIX}* transcript SURVIVES (consumed: build-insights.sh opt-out evidence)" || no "AC-4 review-drain transcript removed"
[ -f "$S4/logs/failures.log" ] && [ -f "$S4/logs/run-1.owner" ] && [ -f "$S4/logs/worktrees.log" ] && ok "AC-4 aged failures.log / *.owner / worktrees.log survive (unrecognised ⇒ untouched)" || no "AC-4 a non-matching logs/ file was removed"
[ -f "$S4/logs/new.jsonl" ] && [ -f "$S4/drain-rounds/ccc-new.json" ] && ok "AC-4 files newer than the threshold survive" || no "AC-4 a new file was removed"
[ -f "$S4/config.json" ] && [ -f "$S4/state.md" ] && [ -f "$S4/.current-session" ] && ok "AC-4 aged top-level entries (dotfile included) survive" || no "AC-4 a top-level entry was removed"
counts_after=""; for d in $NONEXHAUST_DIRS; do counts_after="$counts_after $d=$(count_in "$S4/$d")"; done
[ "$counts_after" = "$counts_before" ] && ok "AC-4 every non-exhaust class keeps its file count ($counts_after )" || no "AC-4 non-exhaust counts changed: before$counts_before after$counts_after"
# AC-5 arm 1
[ -f "$S4/logs/old-unconsumed.jsonl" ] && ok "AC-5 aged UNCONSUMED signal log survives (dreaming-pending)" || no "AC-5 old-unconsumed.jsonl removed"
[ -f "$S4/logs/mid-consumed.jsonl" ] && ok "AC-5 aged consumed log NEWER than the /insights watermark survives (insights-pending)" || no "AC-5 mid-consumed.jsonl removed"
pp_after="$(pending_pair "$F4")"
[ "$pp_after" = "$pp_before" ] && ok "AC-5 status --json dreaming.pending/insights.pending identical before/after ($pp_after)" || no "AC-5 pending changed: before '$pp_before' after '$pp_after'"
# AC-6
[ -f "$S4/zzz-future/aged" ] && ok "AC-6 novel zzz-future/ keeps its aged file" || no "AC-6 zzz-future/aged removed"
printf '%s' "$OUT" | grep -qF 'zzz-future/: unclassified — not swept' && ok "AC-6 report line says 'unclassified — not swept'" || no "AC-6 report line missing"
printf '%s' "$OUT" | grep -qF 'logs/: removed 3 file(s)' && printf '%s' "$OUT" | grep -qF 'drain-rounds/: removed 2 file(s)' \
  && ok "DELETE summary names the count removed per directory" || no "DELETE summary: $(printf '%s\n' "$OUT" | tail -3)"

# ============================================================================
echo "== AC-5 arm 2: cwd is a SECOND, differently-populated fixture; --project-root names the first =="
F5="$ROOT/f5"; build_fixture "$F5"
G5="$ROOT/g5"; build_fixture "$G5"
# Make the second corpus DIFFERENT: its consumed set covers old-unconsumed, so a
# pending set computed from the caller's cwd would let the first fixture's
# unconsumed log be deleted.
printf '{"dreaming":{"consumed":{"logs":["old-consumed","old-unconsumed","mid-consumed","old-noise"]}}}' > "$G5/.supervisor/curation-state.json"
touch -t 202609010000 "$G5/.supervisor/insights/dashboard.md"
printf '{"event":"session_end","id":"g-only"}\n' > "$G5/.supervisor/logs/g-only.jsonl"; touch -t "$OLD" "$G5/.supervisor/logs/g-only.jsonl"
g_before="$(listing "$G5")"
pp5_before="$(pending_pair "$F5")"
run_rs "$RS" "$G5" "$F5" --delete --older-than 1
[ "$RC" -eq 0 ] && ok "AC-5b exits 0" || no "AC-5b rc=$RC"
printf '%s' "$OUT" | grep -qF "root=$(cd "$F5" && pwd -P) " && ok "AC-5b the run names the --project-root, not the cwd" || no "AC-5b root line: $(printf '%s\n' "$OUT" | sed -n 2p)"
[ -f "$F5/.supervisor/logs/old-unconsumed.jsonl" ] && ok "AC-5b the FIRST fixture's aged unconsumed log survives (pending set came from the target, not the cwd)" || no "AC-5b old-unconsumed.jsonl deleted — pending-ids was computed from the caller's cwd"
[ ! -e "$F5/.supervisor/logs/old-consumed.jsonl" ] && ok "AC-5b …while its aged consumed log was removed (the sweep did act on the target)" || no "AC-5b old-consumed.jsonl survived — the sweep did nothing"
[ "$(pending_pair "$F5")" = "$pp5_before" ] && ok "AC-5b first fixture's pending pair unchanged ($pp5_before)" || no "AC-5b pending changed: '$pp5_before' → '$(pending_pair "$F5")'"
[ "$(listing "$G5")" = "$g_before" ] && ok "AC-5b the cwd fixture's listing is byte-identical" || no "AC-5b the cwd fixture was touched"

# ============================================================================
echo "== AC-1b: an aged, committed, TRACKED file inside drain-rounds/ survives =="
F1B="$ROOT/f1b"; build_fixture "$F1B" tracked-in-drain-rounds
h1b="$(hash_of "$F1B/.supervisor/drain-rounds/tracked.json")"
run_rs "$RS" "$F1B" "$F1B" --delete --older-than 1
[ "$RC" -eq 0 ] && ok "AC-1b exits 0" || no "AC-1b rc=$RC"
[ -f "$F1B/.supervisor/drain-rounds/tracked.json" ] && [ "$(hash_of "$F1B/.supervisor/drain-rounds/tracked.json")" = "$h1b" ] \
  && ok "AC-1b tracked file inside an exhaust dir present with unchanged hash" || no "AC-1b tracked.json removed or changed"
[ ! -e "$F1B/.supervisor/drain-rounds/aaa.json" ] && ok "AC-1b control — the untracked aged ledger beside it WAS removed" || no "AC-1b control: aaa.json survived (sweep vacuous)"
printf '%s' "$OUT" | grep -qF 'keep (tracked by git): .supervisor/drain-rounds/tracked.json' && ok "AC-1b the report names the tracked keep" || no "AC-1b keep line missing"

# ============================================================================
echo "== AC-1c: a candidate that becomes TRACKED between the listing pass and the deletion pass survives =="
# mk_git_shim <dir> <root> <rel> [mode] — a `git` on PATH that, on the FIRST
# `ls-files --error-unmatch -- <rel>` probe, performs one action on <rel> and
# answers 1 ("not tracked") — so the change lands AFTER the listing-time answer
# and BEFORE the deletion-time one. Every other call is delegated to the real
# git untouched (the up-front probe, curation-status.sh). Modes:
#   track   (default) stage <rel> for real through the real git
#   rc128   change nothing; every LATER probe for <rel> answers 128
#   rename  mv <rel> to <rel>.moved (the path is no longer a regular file)
#   symlink mv <rel> to <rel>.moved and put a symlink to <root>/link-target
#           in its place
GIT_REAL="$(command -v git)"
mk_git_shim() {
  local d="$1" root="$2" rel="$3" mode="${4:-track}" first="" later=""
  case "$mode" in
    track)   first="\"$GIT_REAL\" -C \"$root\" add -f -- \"$rel\" >/dev/null 2>&1" ;;
    rc128)   first=":"; later="exit 128" ;;
    rename)  first="mv -f \"$root/$rel\" \"$root/$rel.moved\"" ;;
    symlink) first="mv -f \"$root/$rel\" \"$root/$rel.moved\" && ln -s \"$root/link-target\" \"$root/$rel\"" ;;
    *) echo "mk_git_shim: unknown mode $mode" >&2; return 1 ;;
  esac
  mkdir -p "$d"
  cat > "$d/git" <<EOF
#!/bin/sh
case "\$*" in
  *"ls-files --error-unmatch -- $rel"*)
    if [ ! -e "$d/.fired" ]; then
      : > "$d/.fired"
      $first
      exit 1
    fi
    $later ;;
esac
exec "$GIT_REAL" "\$@"
EOF
  chmod +x "$d/git"
}
# listed_in <dir> — how many `would remove:` lines the run listed for that dir.
listed_in() { printf '%s\n' "$OUT" | grep -cF "would remove: .supervisor/$1/"; }
BT_REL=".supervisor/drain-rounds/becomes-tracked.json"
build_bt() {  # <root> — the aged fixture plus an aged, UNTRACKED becomes-tracked.json
  build_fixture "$1"
  printf '{"rounds":0,"max_rounds":5,"becomes":"tracked"}\n' > "$1/$BT_REL"; touch -t "$OLD" "$1/$BT_REL"
}
F1C="$ROOT/f1c"; build_bt "$F1C"; SHIM1C="$ROOT/shim1c"; mk_git_shim "$SHIM1C" "$F1C" "$BT_REL"
h1c="$(hash_of "$F1C/$BT_REL")"
[ "$("$GIT_REAL" -C "$F1C" ls-files --error-unmatch -- "$BT_REL" >/dev/null 2>&1; echo $?)" = "1" ] && ok "AC-1c control — before the run the file is NOT tracked (real git rc 1)" || no "AC-1c control: file already tracked before the run"
OUT="$(cd "$F1C" && PATH="$SHIM1C:$PATH" bash "$RS" --project-root "$F1C" --delete --older-than 1 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "AC-1c exits 0" || no "AC-1c rc=$RC"
[ -e "$SHIM1C/.fired" ] && ok "AC-1c control — the shim fired (the listing-time probe for the file went through it)" || no "AC-1c control: the shim never fired — the arm is vacuous"
[ "$("$GIT_REAL" -C "$F1C" ls-files --error-unmatch -- "$BT_REL" >/dev/null 2>&1; echo $?)" = "0" ] && ok "AC-1c control — after the run the file IS tracked (real git rc 0): it became tracked mid-run" || no "AC-1c control: file not tracked after the run"
printf '%s' "$OUT" | grep -qF "would remove: $BT_REL" && ok "AC-1c the listing pass listed it as would-remove (git said not-tracked at listing time)" || no "AC-1c listing pass did not list the file: $(printf '%s\n' "$OUT" | grep -F drain-rounds | head -5)"
[ -f "$F1C/$BT_REL" ] && [ "$(hash_of "$F1C/$BT_REL")" = "$h1c" ] && ok "AC-1c the file that became tracked between the passes SURVIVES with unchanged hash" || no "AC-1c becomes-tracked.json removed or changed — guard (ii) is not re-evaluated at deletion time"
printf '%s' "$OUT" | grep -qF "keep (tracked at deletion time): $BT_REL" && ok "AC-1c the deletion pass names it 'keep (tracked at deletion time)'" || no "AC-1c deletion-time keep line missing"
[ ! -e "$F1C/.supervisor/drain-rounds/aaa.json" ] && printf '%s' "$OUT" | grep -qF 'drain-rounds/: removed 2 file(s)' && ok "AC-1c control — the two untracked aged ledgers beside it WERE removed and the summary counts what was actually removed (2), not what was listed (3)" || no "AC-1c control: aaa.json survived or summary miscounts: $(printf '%s\n' "$OUT" | tail -3)"

# ============================================================================
echo "== AC-1d: git cannot answer at deletion time (rc 128) ⇒ that file is kept, per file =="
F1D="$ROOT/f1d"; build_bt "$F1D"; SHIM1D="$ROOT/shim1d"; mk_git_shim "$SHIM1D" "$F1D" "$BT_REL" rc128
h1d="$(hash_of "$F1D/$BT_REL")"
OUT="$(cd "$F1D" && PATH="$SHIM1D:$PATH" bash "$RS" --project-root "$F1D" --delete --older-than 1 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "AC-1d exits 0" || no "AC-1d rc=$RC"
[ -e "$SHIM1D/.fired" ] && ok "AC-1d control — the shim fired" || no "AC-1d control: the shim never fired — the arm is vacuous"
printf '%s' "$OUT" | grep -qF 'mode=DELETE' && printf '%s' "$OUT" | grep -qF "would remove: $BT_REL" && ok "AC-1d control — DELETE mode entered and the listing pass listed the file (rc 1 at listing time)" || no "AC-1d control: not DELETE or not listed: $(printf '%s\n' "$OUT" | sed -n 2,4p)"
n1d="$(listed_in drain-rounds)"
[ -f "$F1D/$BT_REL" ] && [ "$(hash_of "$F1D/$BT_REL")" = "$h1d" ] && ok "AC-1d the file git could not answer for at deletion time SURVIVES with unchanged hash" || no "AC-1d becomes-tracked.json removed or changed — rc 128 at deletion time fell through to rm"
printf '%s' "$OUT" | grep -qF "keep (git could not answer at deletion time, rc 128): $BT_REL" && ok "AC-1d the keep line names the file AND the rc (128)" || no "AC-1d keep line missing: $(printf '%s\n' "$OUT" | grep -F 'deletion time' | head -3)"
[ ! -e "$F1D/.supervisor/drain-rounds/aaa.json" ] && [ ! -e "$F1D/.supervisor/drain-rounds/bbb.json" ] && ok "AC-1d the sibling candidates beside it WERE removed (per file, never widened to a refusal)" || no "AC-1d siblings survived — the deletion-time rc widened into a refusal"
[ "$n1d" -eq 3 ] && printf '%s' "$OUT" | grep -qF "drain-rounds/: removed $((n1d - 1)) file(s)" && ok "AC-1d summary counts actual removals: listed $n1d, removed $((n1d - 1))" || no "AC-1d summary miscounts (listed $n1d): $(printf '%s\n' "$OUT" | tail -3)"

# ============================================================================
echo "== AC-1e / AC-1f: candidate renamed away / replaced by a symlink between the passes ⇒ 'skipped (not a regular file now)' =="
for arm in rename symlink; do
  F1E="$ROOT/f1e-$arm"; build_bt "$F1E"; SHIM1E="$ROOT/shim1e-$arm"; mk_git_shim "$SHIM1E" "$F1E" "$BT_REL" "$arm"
  printf 'link target\n' > "$F1E/link-target"; ht="$(hash_of "$F1E/link-target")"
  h1e="$(hash_of "$F1E/$BT_REL")"
  P1E="$(cd "$F1E" && pwd -P)/$BT_REL"   # the tool prints the pwd -P resolved absolute path
  OUT="$(cd "$F1E" && PATH="$SHIM1E:$PATH" bash "$RS" --project-root "$F1E" --delete --older-than 1 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && ok "AC-1e/$arm exits 0" || no "AC-1e/$arm rc=$RC"
  [ -e "$SHIM1E/.fired" ] && printf '%s' "$OUT" | grep -qF "would remove: $BT_REL" && ok "AC-1e/$arm control — the shim fired and the listing pass listed the file" || no "AC-1e/$arm control: shim never fired or file not listed"
  printf '%s' "$OUT" | grep -qF "skipped (not a regular file now): $P1E" && ok "AC-1e/$arm pass 2 prints 'skipped (not a regular file now)' for the path" || no "AC-1e/$arm skip line missing: $(printf '%s\n' "$OUT" | grep -F 'skipped' | head -3)"
  [ -f "$F1E/$BT_REL.moved" ] && [ "$(hash_of "$F1E/$BT_REL.moved")" = "$h1e" ] && ok "AC-1e/$arm the moved-away file is untouched (unchanged hash)" || no "AC-1e/$arm the moved-away file is missing or changed"
  if [ "$arm" = symlink ]; then
    [ -L "$F1E/$BT_REL" ] && [ -f "$F1E/link-target" ] && [ "$(hash_of "$F1E/link-target")" = "$ht" ] && ok "AC-1f the symlink is still in place and its target is untouched (rm never followed the link)" || no "AC-1f symlink removed or its target changed"
  else
    [ ! -e "$F1E/$BT_REL" ] && ok "AC-1e the renamed path stays absent (nothing re-created it)" || no "AC-1e something exists at the renamed path"
  fi
  n1e="$(listed_in drain-rounds)"
  [ "$n1e" -eq 3 ] && [ ! -e "$F1E/.supervisor/drain-rounds/aaa.json" ] && printf '%s' "$OUT" | grep -qF "drain-rounds/: removed $((n1e - 1)) file(s)" && ok "AC-1e/$arm siblings removed; summary counts actual removals: listed $n1e, removed $((n1e - 1))" || no "AC-1e/$arm siblings or summary wrong (listed $n1e): $(printf '%s\n' "$OUT" | tail -3)"
done

# ============================================================================
echo "== AC-1g: a TAB-named candidate is refused at listing time; its same-prefix sibling is never touched =="
# build_tab <root> — the aged fixture plus an aged ledger whose basename holds a
# TAB, and an aged, untracked sibling named exactly the pre-tab prefix (it does
# not match *.json, so it is never a legitimate candidate — the only way it can
# fall is a truncated TSV row naming it).
TAB_BASE="tab-named${TAB}x.json"; TAB_SIB="tab-named"
build_tab() {
  build_fixture "$1"
  printf '{"rounds":0,"max_rounds":5}\n' > "$1/.supervisor/drain-rounds/$TAB_BASE"
  printf 'sibling — must survive\n' > "$1/.supervisor/drain-rounds/$TAB_SIB"
  touch -t "$OLD" "$1/.supervisor/drain-rounds/$TAB_BASE" "$1/.supervisor/drain-rounds/$TAB_SIB"
}
F1G="$ROOT/f1g"; build_tab "$F1G"
[ -f "$F1G/.supervisor/drain-rounds/$TAB_BASE" ] && ok "AC-1g control — the filesystem accepted a tab in the basename" || no "AC-1g control: tab-named fixture not created"
h1g_tab="$(hash_of "$F1G/.supervisor/drain-rounds/$TAB_BASE")"; h1g_sib="$(hash_of "$F1G/.supervisor/drain-rounds/$TAB_SIB")"
run_rs "$RS" "$F1G" "$F1G" --delete --older-than 1
[ "$RC" -eq 0 ] && ok "AC-1g exits 0" || no "AC-1g rc=$RC"
printf '%s' "$OUT" | grep -qF "keep (unsafe name, not swept): .supervisor/drain-rounds/$TAB_BASE" && ok "AC-1g pass 1 prints 'keep (unsafe name, not swept)' for the tab-named file" || no "AC-1g keep line missing: $(printf '%s\n' "$OUT" | grep -F drain-rounds | head -4)"
! printf '%s' "$OUT" | grep -qF "would remove: .supervisor/drain-rounds/$TAB_SIB" && ok "AC-1g the tab-named file is NOT listed as would-remove (no truncated row)" || no "AC-1g a would-remove line names the tab-named file or its prefix"
[ -f "$F1G/.supervisor/drain-rounds/$TAB_BASE" ] && [ "$(hash_of "$F1G/.supervisor/drain-rounds/$TAB_BASE")" = "$h1g_tab" ] && ok "AC-1g the tab-named file survives with unchanged hash" || no "AC-1g tab-named file removed or changed"
[ -f "$F1G/.supervisor/drain-rounds/$TAB_SIB" ] && [ "$(hash_of "$F1G/.supervisor/drain-rounds/$TAB_SIB")" = "$h1g_sib" ] && ok "AC-1g the same-prefix untracked sibling survives with unchanged hash" || no "AC-1g the same-prefix sibling was deleted — a truncated TSV row named it"
[ ! -e "$F1G/.supervisor/drain-rounds/aaa.json" ] && [ "$(listed_in drain-rounds)" -eq 2 ] && printf '%s' "$OUT" | grep -qF 'drain-rounds/: removed 2 file(s)' && ok "AC-1g control — the two safe aged ledgers WERE removed; listed 2, removed 2 (the tab-named file is in neither count)" || no "AC-1g control: counts wrong (listed $(listed_in drain-rounds)): $(printf '%s\n' "$OUT" | tail -3)"
! printf '%s' "$OUT" | grep -qiE 'syntax error|arithmetic' && ok "AC-1g no arithmetic error leaked from a corrupted bytes field" || no "AC-1g arithmetic error in output: $(printf '%s\n' "$OUT" | grep -iE 'syntax error|arithmetic' | head -2)"

# ============================================================================
echo "== AC-7: fail-safe — exit 0, nothing deleted, condition named =="
# (i) unreadable exhaust dirs — chmod 000 does not block root, so skip visibly.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
  skp "AC-7 unreadable-dir arms SKIPPED — running as uid 0, where chmod 000 does not block reads"
else
  F7A="$ROOT/f7a"; build_fixture "$F7A"
  b7a="$(listing "$F7A")"
  chmod 000 "$F7A/.supervisor/logs" "$F7A/.supervisor/drain-rounds"
  run_rs "$RS" "$F7A" "$F7A" --delete --older-than 1
  rc7a=$RC; out7a="$OUT"
  chmod 755 "$F7A/.supervisor/logs" "$F7A/.supervisor/drain-rounds"
  [ "$rc7a" -eq 0 ] && ok "AC-7 unreadable exhaust dirs ⇒ exit 0" || no "AC-7 unreadable rc=$rc7a"
  printf '%s' "$out7a" | grep -qF 'logs/: unreadable — not swept' && printf '%s' "$out7a" | grep -qF 'drain-rounds/: unreadable — not swept' \
    && ok "AC-7 unreadable dirs named as 'unreadable — not swept'" || no "AC-7 unreadable condition not named: $out7a"
  [ "$(listing "$F7A")" = "$b7a" ] && ok "AC-7 unreadable exhaust dirs ⇒ nothing deleted (listing identical)" || no "AC-7 something was deleted around an unreadable dir"
  # never widens: ONE unreadable exhaust dir keeps its files while the other is still swept as designed
  F7B="$ROOT/f7b"; build_fixture "$F7B"
  n7b="$(count_in "$F7B/.supervisor/drain-rounds")"
  chmod 000 "$F7B/.supervisor/drain-rounds"
  run_rs "$RS" "$F7B" "$F7B" --delete --older-than 1
  chmod 755 "$F7B/.supervisor/drain-rounds"
  [ "$RC" -eq 0 ] && [ "$(count_in "$F7B/.supervisor/drain-rounds")" = "$n7b" ] && ok "AC-7 one unreadable dir keeps all $n7b of its files" || no "AC-7 unreadable drain-rounds lost files"
  [ ! -e "$F7B/.supervisor/logs/old-consumed.jsonl" ] && ok "AC-7 …and does not widen to a refusal elsewhere (logs/ still swept per policy)" || no "AC-7 an unreadable dir widened into a whole-run refusal"
fi
# (ii) garbage curation-state.json ⇒ pending-ids prints every id ⇒ no *.jsonl removed
F7C="$ROOT/f7c"; build_fixture "$F7C"
printf 'not json {{{' > "$F7C/.supervisor/curation-state.json"
nj="$(find "$F7C/.supervisor/logs" -name '*.jsonl' | wc -l | tr -d ' ')"
run_rs "$RS" "$F7C" "$F7C" --delete --older-than 1
[ "$RC" -eq 0 ] && ok "AC-7 garbage curation-state.json ⇒ exit 0" || no "AC-7 garbage state rc=$RC"
[ "$(find "$F7C/.supervisor/logs" -name '*.jsonl' | wc -l | tr -d ' ')" = "$nj" ] && ok "AC-7 garbage curation-state.json ⇒ no session log removed (all $nj kept)" || no "AC-7 a session log was removed under a garbage consumed record"
printf '%s' "$OUT" | grep -qF 'pending set is fail-closed' && ok "AC-7 garbage state condition named (pending set is fail-closed)" || no "AC-7 garbage state not named: $(printf '%s\n' "$OUT" | grep -F 'logs' | head -3)"
# (iii)/(iv) PATH without jq / without git
mk_bin() { local d="$1"; shift; mkdir -p "$d"; local t p; for t in "$@"; do p="$(command -v "$t" 2>/dev/null)" || continue; [ -n "$p" ] && ln -sf "$p" "$d/$t"; done; }
BASE_TOOLS="sh bash env date stat find mkdir mv rm cat ls chmod grep sed head tail sort tr wc dirname basename cut uname mktemp touch"
BIN_NOJQ="$ROOT/bin-nojq"; mk_bin "$BIN_NOJQ" $BASE_TOOLS git
BIN_NOGIT="$ROOT/bin-nogit"; mk_bin "$BIN_NOGIT" $BASE_TOOLS jq
for arm in jq git; do
  F7="$ROOT/f7-no$arm"; build_fixture "$F7"; b7="$(listing "$F7")"
  if [ "$arm" = jq ]; then bin="$BIN_NOJQ"; else bin="$BIN_NOGIT"; fi
  OUT="$(cd "$F7" && PATH="$bin" bash "$RS" --project-root "$F7" --delete --older-than 1 2>&1)"; RC=$?
  [ "$RC" -eq 0 ] && ok "AC-7 PATH without $arm ⇒ exit 0" || no "AC-7 no-$arm rc=$RC"
  printf '%s' "$OUT" | grep -qF "$arm unavailable" && printf '%s' "$OUT" | grep -qF 'degraded to REPORT' \
    && ok "AC-7 PATH without $arm ⇒ named, --delete degraded to REPORT" || no "AC-7 no-$arm condition not named: $(printf '%s\n' "$OUT" | sed -n 2,5p)"
  [ "$(listing "$F7")" = "$b7" ] && ok "AC-7 PATH without $arm ⇒ nothing deleted" || no "AC-7 no-$arm deleted something"
done
# (v) non-git --project-root ⇒ rc 128 arm of guard (ii)
F7G="$ROOT/f7g"; build_fixture "$F7G"; rm -rf "$F7G/.git"; b7g="$(listing "$F7G")"
run_rs "$RS" "$F7G" "$F7G" --delete --older-than 1
[ "$RC" -eq 0 ] && ok "AC-7 non-git --project-root ⇒ exit 0" || no "AC-7 non-git rc=$RC"
printf '%s' "$OUT" | grep -qF 'git could not answer (rc 128)' && ok "AC-7 non-git root ⇒ 'git could not answer (rc 128)' named" || no "AC-7 rc-128 not named: $(printf '%s\n' "$OUT" | sed -n 2,5p)"
[ "$(listing "$F7G")" = "$b7g" ] && ok "AC-7 non-git root ⇒ nothing deleted" || no "AC-7 non-git root deleted something"

# ============================================================================
echo "== AC-8: no hook invokes the sweep =="
n8="$(grep -c retention-sweep "$HOOKS" 2>/dev/null)"
[ "$n8" = "0" ] && ok "AC-8 hooks/hooks.json has 0 retention-sweep references" || no "AC-8 hooks.json references retention-sweep ($n8)"

# ============================================================================
echo "== AC-9: mutation controls (one identifiable edit each, asserted RED) =="
MUT="$ROOT/mut"; mkdir -p "$MUT"; cp "$CS" "$MUT/curation-status.sh"   # sibling resolution
mutant() {  # <name> <sed-expr>... — writes $MUT/<name>.sh; fails if the edit did not change anything
  local name="$1"; shift; local f="$MUT/$name.sh"; cp "$RS" "$f"
  local e; for e in "$@"; do sed "$e" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done
  if cmp -s "$RS" "$f"; then no "AC-9 mutant $name: the edit changed NOTHING (control vacuous)"; return 1; fi
  return 0
}
# The mutant scripts live in $MUT, so the sibling curation-status.sh they resolve is the copy there.
# (a1) memory/ + postmortem/ reclassified exhaust (two rows — one verdict).
if mutant a1 "s/^  row memory tracked - /  row memory exhaust '*' /" "s/^  row postmortem tracked - /  row postmortem exhaust '*' /"; then
  FA1="$ROOT/fa1"; build_fixture "$FA1"
  printf 'u\n' > "$FA1/.supervisor/memory/untracked-note.md"; printf 'u\n' > "$FA1/.supervisor/postmortem/untracked.txt"
  touch -t "$OLD" "$FA1/.supervisor/memory/untracked-note.md" "$FA1/.supervisor/postmortem/untracked.txt"
  run_rs "$MUT/a1.sh" "$FA1" "$FA1" --delete --older-than 1
  if [ ! -e "$FA1/.supervisor/memory/untracked-note.md" ] && [ ! -e "$FA1/.supervisor/postmortem/untracked.txt" ]; then
    ok "AC-9 (a1) RED as required: with memory/+postmortem/ reclassified, their aged untracked files are deleted — the verdict, not age, decides"
  else
    no "AC-9 (a1) mutant survived: reclassified rows still untouched (the verdict is not what gates the sweep)"
  fi
  surv=0; for t in $TRACKED; do [ -f "$FA1/.supervisor/$t" ] && surv=$((surv+1)); done
  [ "$surv" -eq 5 ] && ok "AC-9 (a1) …while the five TRACKED files still survive — guard (ii) is independent of the row verdict" || no "AC-9 (a1) tracked files fell to a row edit alone ($surv/5 survive) — the ls-files guard is not live"
fi
# (a2-listing) ONLY the listing-time ls-files guard removed ⇒ the deletion-time
# re-check still keeps the tracked file — asserted GREEN: guard (ii) is layered
# across both passes, and this is the arm that proves the second layer is live
# on its own (without it, removing the listing-time line alone deleted the file).
if mutant a2listing '/# LS-FILES-GUARD$/d'; then
  FA2L="$ROOT/fa2l"; build_fixture "$FA2L" tracked-in-drain-rounds
  run_rs "$MUT/a2listing.sh" "$FA2L" "$FA2L" --delete --older-than 1
  printf '%s' "$OUT" | grep -qF 'would remove: .supervisor/drain-rounds/tracked.json' && ok "AC-9 (a2-listing) control — with the listing-time guard gone the tracked file IS listed as would-remove" || no "AC-9 (a2-listing) control: tracked.json not listed — the listing-time edit did nothing"
  [ -f "$FA2L/.supervisor/drain-rounds/tracked.json" ] && printf '%s' "$OUT" | grep -qF 'keep (tracked at deletion time): .supervisor/drain-rounds/tracked.json' \
    && ok "AC-9 (a2-listing) with ONLY the listing-time guard removed, the deletion-time re-check still keeps the tracked file and names it" || no "AC-9 (a2-listing) tracked.json deleted or keep line missing — the deletion-time guard is not live on its own"
fi
# (a2) BOTH ls-files guard lines removed ⇒ AC-1b red.
if mutant a2 '/# LS-FILES-GUARD$/d' '/# LS-FILES-GUARD-AT-DELETION$/d'; then
  FA2="$ROOT/fa2"; build_fixture "$FA2" tracked-in-drain-rounds
  run_rs "$MUT/a2.sh" "$FA2" "$FA2" --delete --older-than 1
  [ ! -e "$FA2/.supervisor/drain-rounds/tracked.json" ] && ok "AC-9 (a2) RED as required: with BOTH ls-files guard lines removed the tracked file inside drain-rounds/ is deleted" || no "AC-9 (a2) mutant survived: tracked.json kept with both guard lines removed"
fi
# (a3) ONLY the deletion-time guard removed ⇒ AC-1c red (the becomes-tracked file falls).
if mutant a3 '/# LS-FILES-GUARD-AT-DELETION$/d'; then
  FA3="$ROOT/fa3"; build_bt "$FA3"; SHIMA3="$ROOT/shima3"; mk_git_shim "$SHIMA3" "$FA3" "$BT_REL"
  OUT="$(cd "$FA3" && PATH="$SHIMA3:$PATH" bash "$MUT/a3.sh" --project-root "$FA3" --delete --older-than 1 2>&1)"; RC=$?
  [ -e "$SHIMA3/.fired" ] || no "AC-9 (a3) control: the shim never fired"
  [ ! -e "$FA3/$BT_REL" ] && ok "AC-9 (a3) RED as required: without the deletion-time guard the file that became tracked between the passes is deleted" || no "AC-9 (a3) mutant survived: becomes-tracked.json kept without the deletion-time guard"
fi
# (a4) the deletion-time could-not-answer arm deleted ⇒ rc 128 matches no case and falls through to rm ⇒ AC-1d red.
if mutant a4 '/keep (git could not answer at deletion time/d'; then
  FA4="$ROOT/fa4"; build_bt "$FA4"; SHIMA4="$ROOT/shima4"; mk_git_shim "$SHIMA4" "$FA4" "$BT_REL" rc128
  OUT="$(cd "$FA4" && PATH="$SHIMA4:$PATH" bash "$MUT/a4.sh" --project-root "$FA4" --delete --older-than 1 2>&1)"; RC=$?
  [ -e "$SHIMA4/.fired" ] || no "AC-9 (a4) control: the shim never fired"
  [ ! -e "$FA4/$BT_REL" ] && ok "AC-9 (a4) RED as required: without the could-not-answer arm, rc 128 at deletion time falls through to rm and the file is deleted" || no "AC-9 (a4) mutant survived: becomes-tracked.json kept without the arm"
fi
# (a5) the unsafe-name guard removed ⇒ the tab-named row is enqueued split, pass 2 reads the
# pre-tab prefix as the path and rm's the same-prefix sibling ⇒ AC-1g red.
if mutant a5 '/# UNSAFE-NAME-GUARD$/d'; then
  FA5="$ROOT/fa5"; build_tab "$FA5"
  run_rs "$MUT/a5.sh" "$FA5" "$FA5" --delete --older-than 1
  [ ! -e "$FA5/.supervisor/drain-rounds/$TAB_SIB" ] && ok "AC-9 (a5) RED as required: without the unsafe-name guard the same-prefix sibling of a tab-named candidate is deleted" || no "AC-9 (a5) mutant survived: the sibling was kept without the guard"
  [ -f "$FA5/.supervisor/drain-rounds/$TAB_BASE" ] && ok "AC-9 (a5) …while the tab-named file itself is untouched (the truncated row never named it) — the damage is to a file the report never listed" || no "AC-9 (a5) the tab-named file was removed (unexpected: the row names its prefix, not it)"
fi
# (a1+a2) rows reclassified + both guard lines down ⇒ AC-1 proper (the five hashes) red — the layering claim.
if mutant a1a2 "s/^  row memory tracked - /  row memory exhaust '*' /" "s/^  row postmortem tracked - /  row postmortem exhaust '*' /" '/# LS-FILES-GUARD$/d' '/# LS-FILES-GUARD-AT-DELETION$/d'; then
  FA12="$ROOT/fa12"; build_fixture "$FA12"
  run_rs "$MUT/a1a2.sh" "$FA12" "$FA12" --delete --older-than 1
  gone=0; for t in $TRACKED; do [ -e "$FA12/.supervisor/$t" ] || gone=$((gone+1)); done
  [ "$gone" -eq 5 ] && ok "AC-9 (a1+a2) RED as required: only with the rows reclassified AND both guard lines removed do all five tracked files fall ($gone/5)" || no "AC-9 (a1+a2) mutant survived: $gone/5 tracked files deleted with both guards removed"
fi
# (b) the two guard rows reclassified exhaust ⇒ AC-2 red.
if mutant b "s/^  row review-dispatch guard - /  row review-dispatch exhaust '*' /" "s/^  row postmortem-dispatch guard - /  row postmortem-dispatch exhaust '*' /"; then
  FB="$ROOT/fb"; build_fixture "$FB"
  run_rs "$MUT/b.sh" "$FB" "$FB" --delete --older-than 1
  [ ! -e "$FB/.supervisor/review-dispatch/deadbeef" ] && [ ! -e "$FB/.supervisor/postmortem-dispatch/deadbeef" ] \
    && ok "AC-9 (b) RED as required: reclassified guard rows lose their aged markers — the guard verdict is what keeps them" || no "AC-9 (b) mutant survived: markers kept without the guard verdict"
fi
# (c) the pending-ids exclusion line removed ⇒ AC-5 red.
if mutant c '/# PENDING-IDS-EXCLUSION$/d'; then
  FC="$ROOT/fc"; build_fixture "$FC"; ppc="$(pending_pair "$FC")"
  run_rs "$MUT/c.sh" "$FC" "$FC" --delete --older-than 1
  [ ! -e "$FC/.supervisor/logs/old-unconsumed.jsonl" ] && ok "AC-9 (c) RED as required: without the exclusion the aged UNCONSUMED log is deleted" || no "AC-9 (c) mutant survived: old-unconsumed.jsonl kept without the exclusion"
  [ "$(pending_pair "$FC")" != "$ppc" ] && ok "AC-9 (c) …and status --json's pending pair CHANGED ($ppc → $(pending_pair "$FC")) — the amnesia AC-5 exists to catch" || no "AC-9 (c) pending pair unchanged ($ppc) — AC-5 would not have caught the mutant"
fi

# ============================================================================
echo "== AC-10: policy mirror — script table ⇔ ARCHITECTURE_CONTRACTS.md, both directions =="
script_policy="$(bash "$RS" policy | LC_ALL=C sort)"
# Rows of the retention-policy section: first cell = backticked dir (`memory/` → memory; `.` → .), second = class.
doc_policy="$(awk '/^## `\.supervisor\/` retention policy/{f=1; next} f && /^## /{f=0} f && /^\| `/{print}' "$CONTRACTS" \
  | awk -F'|' '{d=$2; c=$3; gsub(/^[ \t]+|[ \t]+$/, "", d); gsub(/^[ \t]+|[ \t]+$/, "", c); sub(/^`/, "", d); sub(/`.*$/, "", d); sub(/\/$/, "", d); gsub(/`/, "", c); print d "\t" c}' \
  | LC_ALL=C sort)"
[ -n "$script_policy" ] && ok "AC-10 'policy' prints $(printf '%s\n' "$script_policy" | grep -c .) dir<TAB>class lines" || no "AC-10 'policy' printed nothing"
[ -n "$doc_policy" ] && ok "AC-10 the doc section yields $(printf '%s\n' "$doc_policy" | grep -c .) rows" || no "AC-10 no retention table rows parsed from ARCHITECTURE_CONTRACTS.md"
if [ "$script_policy" = "$doc_policy" ]; then
  ok "AC-10 script policy and doc table are identical (same dirs, same classes, both directions)"
else
  no "AC-10 policy mirror drift:"; diff <(printf '%s\n' "$script_policy") <(printf '%s\n' "$doc_policy") | sed 's/^/      /'
fi
printf '%s\n' "$script_policy" | grep -qx "logs${TAB}consumed → partial exhaust" && ok "AC-10 logs/ carries the partial-exhaust class in the machine surface" || no "AC-10 logs/ class wrong: $(printf '%s\n' "$script_policy" | grep '^logs')"
[ "$(printf '%s\n' "$script_policy" | grep -c "${TAB}.*exhaust")" = "2" ] && ok "AC-10 exactly two rows carry an exhaust class (logs, drain-rounds)" || no "AC-10 exhaust row count != 2"

echo
if [ "$skip" -gt 0 ]; then echo "RESULT: $pass passed, $fail failed, $skip skipped"; else echo "RESULT: $pass passed, $fail failed"; fi
[ "$fail" -eq 0 ] || exit 1
exit 0
