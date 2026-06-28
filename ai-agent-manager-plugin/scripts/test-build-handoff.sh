#!/usr/bin/env bash
# test-build-handoff.sh — self-tests for build-handoff.sh, the read-only "catch up / hand off in
# 2 minutes" digest assembler (Subtask 2 of the handoff-digest job). Runs in isolated temp git
# repos via `mktemp -d` and writes ONLY to each temp repo's own .supervisor/handoff/ (NEVER touches
# the real .supervisor/ or runs build-handoff.sh against the real repo). Mirrors the
# test-build-vault.sh harness convention. Exit 0 = all pass, 1 = any failure (auto-registered by
# ci.yml's test-*.sh glob).
#
# Covers AC9 cases (a)–(g):
#   (a) mode-agnostic assembly — a jobs brief AND an autonomous-dir item land in ONE digest
#   (b) absent-surface no-op — no .supervisor/automate/ → still exit 0 + valid digest
#   (c) no-surfaces-at-all — empty/absent .supervisor/ → benign "nothing to summarize" + exit 0
#   (d) freshness stale → emit-with-hint — SHA-trailer fixture w/ SHA != HEAD → `hint` w/ BOTH SHAs,
#       item still present (not dropped)
#   (e) read-only invariant — every seeded source-of-truth surface byte-identical before/after; the
#       ONLY new/changed paths are under .supervisor/handoff/ PLUS sanctioned logs/{memory,twin}.log
#   (f) reuse path — build-handoff.sh source references read-project-memory.sh + read-lessons.sh
#   (g) freshness contrast — commit-bearing item renders `hint` WITH SHAs; commit-less item renders
#       `unknown` WITH NO SHA comparison (its line carries no `hint —` token)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build-handoff.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# All temp dirs live under ONE root so a single trap reliably cleans everything.
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

# mktmp — allocate a fresh temp subdir UNDER $ROOT and echo its path.
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# Create an isolated temp git repo and echo its path.
new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# Run build-handoff.sh inside a temp repo. cd so its `git rev-parse --show-toplevel` resolves to
# the temp repo; CLAUDE_PLUGIN_ROOT=$HERE so the reused read-* helpers resolve to the real scripts.
run_build() {
  local repo="$1"
  ( cd "$repo" && CLAUDE_PLUGIN_ROOT="$HERE" bash "$BUILD" )
}

# Cross-platform mtime in seconds (GNU stat -c, BSD/macOS stat -f).
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# Checksum helper (sha256sum || shasum || cksum).
csum() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

# Seed a minimal Supervisor job brief under a repo's lifecycle dir. Echoes the file path.
#   $1 repo  $2 lifecycle (pending|in-progress|done|failed)  $3 basename(no .md)  $4 extra md lines
seed_job() {
  local repo="$1" lc="$2" name="$3" extra="${4:-}"
  mkdir -p "$repo/.supervisor/jobs/$lc"
  local f="$repo/.supervisor/jobs/$lc/$name.md"
  {
    printf '# %s\n\n' "$name"
    printf -- '- **Goal:** ship the %s thing\n' "$name"
    [ -n "$extra" ] && printf '%s\n' "$extra"
  } > "$f"
  printf '%s' "$f"
}

# Seed a minimal autonomous session dir with a state.json. Echoes the dir path.
seed_auto() {
  local repo="$1" sid="${2:-sess-auto-1}"
  mkdir -p "$repo/.supervisor/autonomous/$sid"
  printf '%s\n' '{"mode":"single","iteration":1,"max_iterations":3,"requirement_path":".supervisor/requirements/x.md","iterations":[{"summary":"did the thing","supervisor_status":"completed","heal_decision":"PASS"}],"ended_at":"2026-06-05T10:00:00Z"}' \
    > "$repo/.supervisor/autonomous/$sid/state.json"
  printf '%s' "$repo/.supervisor/autonomous/$sid"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "test-build-handoff: jq absent — build-handoff.sh no-ops (exit 0). Skipping data assertions."
  echo "RESULT: 0 passed, 0 failed (jq absent, vacuous)"
  exit 0
fi

# ============================================================================
echo "== (a) mode-agnostic assembly: a job AND an autonomous run in ONE digest =="
RA="$(new_repo)"
JOBA="$(seed_job "$RA" done "alpha-feature")"
seed_auto "$RA" "sess-a" >/dev/null
outA="$(run_build "$RA")"; rcA=$?
DIGA="$RA/.supervisor/handoff/digest.md"
[ "$rcA" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcA"
[ -f "$DIGA" ] && ok "digest written" || no "digest missing at $DIGA"
echo "$outA" | grep -qF "wrote .supervisor/handoff/digest.md" && ok "echoes the output path" || no "output-path echo missing"
# Both items present in ONE unified list.
grep -qF "alpha-feature" "$DIGA" 2>/dev/null && ok "job item present in digest" || no "job item missing"
grep -qF "sess-a" "$DIGA" 2>/dev/null && ok "autonomous item present in digest" || no "autonomous item missing"
# One unified header (not three per-mode digests).
grep -qF "Recent work items (newest first, mode-agnostic" "$DIGA" 2>/dev/null \
  && ok "single mode-agnostic work-item list rendered" || no "unified work-item header missing"

# ============================================================================
echo "== (b) absent-surface no-op: NO .supervisor/automate/ → exit 0 + valid digest =="
RB="$(new_repo)"
seed_job "$RB" pending "beta-task" >/dev/null
[ -d "$RB/.supervisor/automate" ] && no "precondition: automate/ should be absent" || ok "precondition: no .supervisor/automate/ dir"
outB="$(run_build "$RB")"; rcB=$?
DIGB="$RB/.supervisor/handoff/digest.md"
[ "$rcB" -eq 0 ] && ok "exits 0 with automate surface absent" || no "expected exit 0, got $rcB"
[ -f "$DIGB" ] && grep -qF "beta-task" "$DIGB" 2>/dev/null \
  && ok "valid digest produced with the absent surface skipped" || no "digest missing/invalid"

# ============================================================================
echo "== (c) no-surfaces-at-all: empty .supervisor/ → benign nothing-to-summarize + exit 0 =="
RC="$(new_repo)"
# A bare repo: no .supervisor/ at all.
outC="$(run_build "$RC")"; rcC=$?
DIGC="$RC/.supervisor/handoff/digest.md"
[ "$rcC" -eq 0 ] && ok "exits 0 with no continuity surfaces" || no "expected exit 0, got $rcC"
[ -f "$DIGC" ] && ok "digest still written (benign)" || no "digest missing for empty repo"
grep -qF "Nothing to summarize yet" "$DIGC" 2>/dev/null \
  && ok "benign 'nothing to summarize' line present" || no "nothing-to-summarize line missing"

# ============================================================================
echo "== (d) freshness stale → emit-with-hint (SHA != HEAD), item NOT dropped =="
RD="$(new_repo)"
FAKE_SHA="deadbeefcafe1234567890abcdef1234567890ab"   # 40 hex, != HEAD
HEADD="$( cd "$RD" && git rev-parse HEAD )"
seed_job "$RD" done "stale-item" "- **built_at_commit:** $FAKE_SHA" >/dev/null
outD="$(run_build "$RD")"; rcD=$?
DIGD="$RD/.supervisor/handoff/digest.md"
[ "$rcD" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcD"
grep -qF "stale-item" "$DIGD" 2>/dev/null && ok "stale item still present (not dropped)" || no "stale item was dropped"
# Hint line carries BOTH the basis SHA (first 8) and the HEAD SHA (first 8).
if grep -q "hint — basis ${FAKE_SHA:0:8}, HEAD ${HEADD:0:8}" "$DIGD" 2>/dev/null; then
  ok "hint line renders BOTH basis and HEAD short SHAs"
else
  no "expected 'hint — basis ${FAKE_SHA:0:8}, HEAD ${HEADD:0:8}'; got: $(grep -F 'hint —' "$DIGD" 2>/dev/null || echo '<no hint line>')"
fi

# ============================================================================
echo "== (e) read-only invariant: sources byte-identical; only handoff/ + sanctioned logs change =="
RE="$(new_repo)"
# Seed a representative spread of source-of-truth surfaces.
JOBE="$(seed_job "$RE" done "readonly-job" "- **built_at_commit:** $( cd "$RE" && git rev-parse HEAD )")"
seed_auto "$RE" "sess-e" >/dev/null
STATE_E="$RE/.supervisor/state.md"
printf -- '- session_id: sess-e\n- status: completed\n- phase: FINALIZE\n- branch: feature/x\n' > "$STATE_E"
mkdir -p "$RE/.supervisor/memory" "$RE/.supervisor/logs"
MEM_E="$RE/.supervisor/memory/PROJECT_MEMORY.md"
printf '# Project Memory\n\n- a durable fact\n' > "$MEM_E"
LOG_E="$RE/.supervisor/logs/sess-e.jsonl"
printf '%s\n' '{"event":"session_end","status":"completed"}' > "$LOG_E"
AUTOJSON_E="$RE/.supervisor/autonomous/sess-e/state.json"

# Snapshot checksums of every source-of-truth surface BEFORE the run.
job_b="$(csum "$JOBE")"; state_b="$(csum "$STATE_E")"; mem_b="$(csum "$MEM_E")"
log_b="$(csum "$LOG_E")"; auto_b="$(csum "$AUTOJSON_E")"

# Pre-run inventory of every existing path under .supervisor/ (to detect stray creations).
INV_BEFORE="$(mktmp)/inv.before"; mkdir -p "$(dirname "$INV_BEFORE")"
( cd "$RE" && find .supervisor -type f 2>/dev/null | sort ) > "$INV_BEFORE"

run_build "$RE" >/dev/null; rcE=$?
[ "$rcE" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcE"

# All source-of-truth surfaces must be byte-identical.
all_unchanged=1
[ "$job_b"   = "$(csum "$JOBE")" ]      || { all_unchanged=0; echo "    changed: job brief"; }
[ "$state_b" = "$(csum "$STATE_E")" ]   || { all_unchanged=0; echo "    changed: state.md"; }
[ "$mem_b"   = "$(csum "$MEM_E")" ]     || { all_unchanged=0; echo "    changed: PROJECT_MEMORY.md"; }
[ "$log_b"   = "$(csum "$LOG_E")" ]     || { all_unchanged=0; echo "    changed: session jsonl"; }
[ "$auto_b"  = "$(csum "$AUTOJSON_E")" ] || { all_unchanged=0; echo "    changed: autonomous state.json"; }
[ "$all_unchanged" -eq 1 ] && ok "all seeded source-of-truth surfaces byte-identical" || no "a source-of-truth surface was modified"

# Any NEW path under .supervisor/ must be under handoff/ OR the sanctioned logs/{memory,twin}.log.
INV_AFTER="$(mktmp)/inv.after"; mkdir -p "$(dirname "$INV_AFTER")"
( cd "$RE" && find .supervisor -type f 2>/dev/null | sort ) > "$INV_AFTER"
stray=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    .supervisor/handoff/*) ;;                                   # sanctioned: our own output
    .supervisor/logs/memory.log|.supervisor/logs/twin.log) ;;   # sanctioned: reused readers' diagnostics
    *) grep -qxF "$p" "$INV_BEFORE" || { stray=$((stray+1)); echo "    stray new path: $p"; } ;;
  esac
done < "$INV_AFTER"
[ "$stray" -eq 0 ] && ok "only handoff/ + sanctioned {memory,twin}.log are new/changed" || no "$stray stray new path(s) outside the sanctioned set"
# Positively confirm the run actually produced its output.
[ -f "$RE/.supervisor/handoff/digest.md" ] && ok "digest produced under .supervisor/handoff/" || no "digest not produced"

# ============================================================================
echo "== (f) reuse path: build-handoff.sh invokes the existing readers (grep-of-source) =="
grep -qF "read-project-memory.sh" "$BUILD" && ok "references read-project-memory.sh" || no "no reference to read-project-memory.sh"
grep -qF "read-lessons.sh" "$BUILD" && ok "references read-lessons.sh" || no "no reference to read-lessons.sh"

# ============================================================================
echo "== (g) freshness contrast: commit-bearing → hint w/ SHAs; commit-less → unknown, no SHA =="
RG="$(new_repo)"
FAKE_G="0123456789abcdef0123456789abcdef01234567"   # 40 hex, != HEAD
HEADG="$( cd "$RG" && git rev-parse HEAD )"
seed_job "$RG" done "commit-bearing-item" "- **built_at_commit:** $FAKE_G" >/dev/null
seed_job "$RG" done "commit-less-item" >/dev/null   # NO SHA trailer
run_build "$RG" >/dev/null; rcG=$?
DIGG="$RG/.supervisor/handoff/digest.md"
[ "$rcG" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcG"
# The commit-bearing item renders a hint WITH both SHAs.
grep -q "hint — basis ${FAKE_G:0:8}, HEAD ${HEADG:0:8}" "$DIGG" 2>/dev/null \
  && ok "commit-bearing item renders 'hint' with both SHAs" || no "commit-bearing hint line missing"
# Isolate the commit-less item's section and assert its freshness line is 'unknown' with NO hint.
# awk: print lines from the commit-less '### ' heading up to (but not incl.) the next '### ' heading.
LESS_SECTION="$(awk '/^### commit-less-item$/{f=1} f&&/^### / && !/^### commit-less-item$/{exit} f' "$DIGG" 2>/dev/null)"
echo "$LESS_SECTION" | grep -qF "freshness unknown (no commit SHA recorded)" \
  && ok "commit-less item renders 'freshness unknown' (mtime basis)" || no "commit-less item missing 'freshness unknown' line"
echo "$LESS_SECTION" | grep -qF "hint —" \
  && no "commit-less item incorrectly shows a 'hint —' SHA comparison" || ok "commit-less item shows NO 'hint —' SHA comparison"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
