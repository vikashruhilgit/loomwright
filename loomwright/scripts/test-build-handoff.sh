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
#   (h) real producer Outcome facets — a real `## Outcome` brief renders Status / Heal decision /
#       Heal iterations / PR facets (keys match agents/supervisor.md, not the old lowercase keys)
#   (i) reader resolution — with CLAUDE_PLUGIN_ROOT set to the plugin ROOT, the read-* helpers
#       resolve under $CLAUDE_PLUGIN_ROOT/scripts and their output is incorporated (finding #1)
#   (j) abbreviated-SHA freshness — a recorded short SHA that prefixes HEAD renders `fresh`, not
#       `hint` (prefix-tolerant compare; finding #2)
#   (k) real automate run-file — a /automate run-file's Status / Source / PR facets render (finding #3)

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

# The REAL plugin root is the parent of the scripts dir ($HERE). CLAUDE_PLUGIN_ROOT points at the
# plugin ROOT at runtime (NOT the scripts dir) — the read-* helpers live under its scripts/ subdir.
# Simulating it correctly here is what catches the finding-#1 class of helper-path bug.
PLUGIN_ROOT="$(dirname "$HERE")"

# Run build-handoff.sh inside a temp repo. cd so its `git rev-parse --show-toplevel` resolves to
# the temp repo; CLAUDE_PLUGIN_ROOT=$PLUGIN_ROOT so the reused read-* helpers resolve to
# $PLUGIN_ROOT/scripts (the real plugin layout), exactly as in production.
run_build() {
  local repo="$1"
  ( cd "$repo" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$BUILD" )
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

# Seed a done job with a REAL Supervisor completion-tail `## Outcome` block (agents/supervisor.md
# "## Outcome": **Status:** / **PR:** / **Heal loop ran:** / **Heal decision:** / **Heal iterations:**
# / **Summary:**). The Goal lives under `## Task` as the bare `**Goal:**` form real briefs use.
seed_job_outcome() {
  local repo="$1" name="$2"
  mkdir -p "$repo/.supervisor/jobs/done"
  local f="$repo/.supervisor/jobs/done/$name.md"
  {
    printf '# %s\n\n' "$name"
    printf '## Task\n**Goal:** ship the %s thing\n\n' "$name"
    printf '## Outcome\n'
    printf -- '- **Status:** completed\n'
    printf -- '- **PR:** https://github.com/o/r/pull/99\n'
    printf -- '- **Heal loop ran:** true\n'
    printf -- '- **Heal decision:** PASS\n'
    printf -- '- **Heal iterations:** 2\n'
    printf -- '- **Summary:** did the %s thing well\n' "$name"
  } > "$f"
  printf '%s' "$f"
}

# Seed a REAL /automate run-file (skills/automate-loop/SKILL.md "Run-file template"). Echoes the path.
seed_automate() {
  local repo="$1" name="$2"
  mkdir -p "$repo/.supervisor/automate"
  local f="$repo/.supervisor/automate/$name.md"
  {
    printf '# Automate Run: %s\n' "$name"
    printf '## Status: paused\n'
    printf '## Source\n- folder .supervisor/requirements/\n'
    printf '## Run Config\n- mode: safe | limit: 5\n'
    printf '## Queue\n- [x] req-a.md\n- [ ] req-b.md\n'
    printf '## Current\n- item: req-a.md | status: awaiting_merge | pr: https://github.com/o/r/pull/77 | branch: feature/req-a\n'
    printf '## Progress\n- ts ran /autonomous\n'
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

# ============================================================================
echo "== (h) real producer Outcome facets render (Status / Heal decision / Heal iterations / PR) =="
RH="$(new_repo)"
seed_job_outcome "$RH" "real-outcome-item" >/dev/null
run_build "$RH" >/dev/null; rcH=$?
DIGH="$RH/.supervisor/handoff/digest.md"
[ "$rcH" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcH"
SECTH="$(awk '/^### real-outcome-item$/{f=1} f&&/^### / && !/^### real-outcome-item$/{exit} f' "$DIGH" 2>/dev/null)"
echo "$SECTH" | grep -qF "completed" \
  && ok "Status facet renders (decision shows '— completed')" || no "Status facet missing (decision didn't pick up **Status:**)"
echo "$SECTH" | grep -qF "self-heal PASS" \
  && ok "Heal decision facet renders (tried/rejected shows 'self-heal PASS')" || no "Heal decision facet missing"
echo "$SECTH" | grep -qF "https://github.com/o/r/pull/99" \
  && ok "PR facet renders" || no "PR facet missing"
echo "$SECTH" | grep -qF "ship the real-outcome-item thing" \
  && ok "Goal (why) facet renders from the bare **Goal:** under ## Task" || no "Goal facet missing"
# Legacy lowercase/underscore Outcome keys must ALSO render (real briefs carry both casings).
RH2="$(new_repo)"
mkdir -p "$RH2/.supervisor/jobs/done"
{ printf '# legacy-keys-item\n\n## Outcome\n'; printf -- '- **status:** completed\n'; \
  printf -- '- **heal_decision:** PASS\n'; printf -- '- **heal_iterations:** 1\n'; } > "$RH2/.supervisor/jobs/done/legacy-keys-item.md"
run_build "$RH2" >/dev/null
SECTH2="$(awk '/^### legacy-keys-item$/{f=1} f&&/^### / && !/^### legacy-keys-item$/{exit} f' "$RH2/.supervisor/handoff/digest.md" 2>/dev/null)"
echo "$SECTH2" | grep -qF "self-heal PASS" \
  && ok "legacy lowercase heal_decision key still renders (dual-casing fallback)" || no "legacy lowercase Outcome keys not picked up"

# ============================================================================
echo "== (i) reader resolution: CLAUDE_PLUGIN_ROOT=plugin-root resolves readers under scripts/ (finding #1) =="
RI="$(new_repo)"
seed_job "$RI" done "reader-host" >/dev/null
SHIMROOT="$(mktmp)"; mkdir -p "$SHIMROOT/scripts"
printf '#!/usr/bin/env bash\necho "SHIM_MEMORY_SENTINEL_42"\n' > "$SHIMROOT/scripts/read-project-memory.sh"
printf '#!/usr/bin/env bash\necho "SHIM_LESSONS_SENTINEL_42"\n' > "$SHIMROOT/scripts/read-lessons.sh"
chmod +x "$SHIMROOT/scripts/read-project-memory.sh" "$SHIMROOT/scripts/read-lessons.sh"
( cd "$RI" && CLAUDE_PLUGIN_ROOT="$SHIMROOT" bash "$BUILD" ) >/dev/null; rcI=$?
DIGI="$RI/.supervisor/handoff/digest.md"
[ "$rcI" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcI"
grep -qF "SHIM_MEMORY_SENTINEL_42" "$DIGI" 2>/dev/null \
  && ok "read-project-memory.sh resolved under \$CLAUDE_PLUGIN_ROOT/scripts and its output incorporated" \
  || no "memory reader NOT resolved under \$CLAUDE_PLUGIN_ROOT/scripts (finding #1 regression)"
grep -qF "SHIM_LESSONS_SENTINEL_42" "$DIGI" 2>/dev/null \
  && ok "read-lessons.sh resolved under \$CLAUDE_PLUGIN_ROOT/scripts and its output incorporated" \
  || no "lessons reader NOT resolved under \$CLAUDE_PLUGIN_ROOT/scripts (finding #1 regression)"

# ============================================================================
echo "== (j) abbreviated recorded SHA prefixes HEAD → 'fresh', not 'hint' (finding #2) =="
RJ="$(new_repo)"
SHORTJ="$( cd "$RJ" && git rev-parse --short HEAD )"   # abbreviated current HEAD (prefix of full HEAD)
seed_job "$RJ" done "fresh-short-sha" "- **built_at_commit:** $SHORTJ" >/dev/null
run_build "$RJ" >/dev/null; rcJ=$?
DIGJ="$RJ/.supervisor/handoff/digest.md"
[ "$rcJ" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcJ"
SECTJ="$(awk '/^### fresh-short-sha$/{f=1} f&&/^### / && !/^### fresh-short-sha$/{exit} f' "$DIGJ" 2>/dev/null)"
echo "$SECTJ" | grep -qF "fresh (basis" \
  && ok "abbreviated HEAD SHA renders 'fresh' (prefix-tolerant)" \
  || no "abbreviated HEAD SHA not 'fresh'; got: $(echo "$SECTJ" | grep -E 'fresh|hint —' || echo '<none>')"
echo "$SECTJ" | grep -qF "hint —" \
  && no "abbreviated HEAD SHA wrongly shows 'hint' (finding #2 regression)" \
  || ok "no false 'hint' for a fresh abbreviated SHA"

# ============================================================================
echo "== (k) real /automate run-file: Status / Source / PR facets render (finding #3) =="
RK="$(new_repo)"
seed_automate "$RK" "automate-run-1" >/dev/null
run_build "$RK" >/dev/null; rcK=$?
DIGK="$RK/.supervisor/handoff/digest.md"
[ "$rcK" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcK"
SECTK="$(awk '/^### automate-run-1$/{f=1} f&&/^### / && !/^### automate-run-1$/{exit} f' "$DIGK" 2>/dev/null)"
echo "$SECTK" | grep -qF "automate run — paused" \
  && ok "automate Status facet renders (decision shows '— paused')" || no "automate Status facet missing"
echo "$SECTK" | grep -qF "folder .supervisor/requirements/" \
  && ok "automate Source facet renders (why)" || no "automate Source facet missing"
echo "$SECTK" | grep -qF "https://github.com/o/r/pull/77" \
  && ok "automate PR facet renders (from ## Current)" || no "automate PR facet missing"

# ============================================================================
echo "== (l) AC-handoff-byte-identical: default (no-flag) output matches the PRE-CHANGE script byte-for-byte =="
# PRECHANGE_SHA is the commit immediately before the --publish flag was added to build-handoff.sh
# (subtask 3 of the archive-views job). Pinning to a real commit — not reasoning that the flag is
# "additive" — is what makes this a mechanized proof rather than an assertion by inspection.
PRECHANGE_SHA="2682ed2"
GITROOT="$(cd "$HERE" && git rev-parse --show-toplevel 2>/dev/null)"
RL="$(new_repo)"
seed_job "$RL" done "byte-identical-job" "- **built_at_commit:** $( cd "$RL" && git rev-parse HEAD )" >/dev/null
seed_auto "$RL" "sess-l" >/dev/null
seed_automate "$RL" "automate-l" >/dev/null
if [ -n "$GITROOT" ] && git -C "$GITROOT" cat-file -e "$PRECHANGE_SHA:loomwright/scripts/build-handoff.sh" 2>/dev/null; then
  PRE_SCRIPT="$ROOT/pre-build-handoff.sh"
  git -C "$GITROOT" show "$PRECHANGE_SHA:loomwright/scripts/build-handoff.sh" > "$PRE_SCRIPT" 2>/dev/null
  # Run the PRE-CHANGE script against the fixture first (no flag — it predates --publish anyway).
  ( cd "$RL" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PRE_SCRIPT" ) >/dev/null 2>&1; rcPre=$?
  DIGL="$RL/.supervisor/handoff/digest.md"
  [ "$rcPre" -eq 0 ] && [ -f "$DIGL" ] && ok "pre-change script ran and produced a digest" \
    || no "pre-change script failed to produce a digest (rc=$rcPre)"
  PRE_OUT="$RL/.pre-digest-snapshot.md"
  cp "$DIGL" "$PRE_OUT" 2>/dev/null
  # Now run the POST-CHANGE (current) script, NO --publish flag, over the SAME fixture inputs.
  run_build "$RL" >/dev/null; rcPost=$?
  [ "$rcPost" -eq 0 ] && ok "post-change default (no-flag) run exits 0" || no "post-change run failed (rc=$rcPost)"
  # The two runs are separate invocations of `date -u` seconds apart in real wall-clock time — that
  # non-determinism predates this change (unrelated to --publish) and is not what this AC is testing.
  # Strip ONLY the volatile `_Generated <ts>` line before comparing everything else byte-for-byte.
  PRE_FILT="$RL/.pre-digest-filtered.md"; POST_FILT="$RL/.post-digest-filtered.md"
  grep -v '^_Generated ' "$PRE_OUT" > "$PRE_FILT"
  grep -v '^_Generated ' "$DIGL"    > "$POST_FILT"
  if diff -q "$PRE_FILT" "$POST_FILT" >/dev/null 2>&1; then
    ok "AC-handoff-byte-identical: default digest.md is byte-identical pre- vs post-change (diff empty, excluding the volatile generation timestamp)"
  else
    no "default digest.md DIFFERS pre- vs post-change: $(diff "$PRE_FILT" "$POST_FILT" 2>&1 | head -5)"
  fi
  # Sanity control: prove the diff comparison itself can discriminate (else the assertion above would
  # be vacuous — a diff command that never reports a difference would pass unconditionally).
  CORRUPT="$RL/.pre-digest-corrupt.md"
  { cat "$PRE_FILT"; echo "MUTATION_CONTROL_SENTINEL"; } > "$CORRUPT"
  diff -q "$PRE_FILT" "$CORRUPT" >/dev/null 2>&1 && no "control: diff failed to detect a deliberately corrupted copy" \
    || ok "control: diff correctly detects a deliberately corrupted copy (comparison is not vacuous)"
else
  echo "  SKIPPED — pinned commit $PRECHANGE_SHA:loomwright/scripts/build-handoff.sh not reachable in this checkout"
fi

# ============================================================================
echo "== (m) absent --publish flag: no snapshot.md written, no new code path executes =="
RM="$(new_repo)"
seed_job "$RM" pending "no-publish-item" >/dev/null
run_build "$RM" >/dev/null; rcM=$?
SNAPM="$RM/.supervisor/handoff/snapshot.md"
[ "$rcM" -eq 0 ] && ok "exits 0 with no flag" || no "expected exit 0, got $rcM"
[ -f "$SNAPM" ] && no "snapshot.md was written despite NO --publish flag (publish path leaked)" \
  || ok "no snapshot.md written absent --publish (AC-handoff-byte-identical: no new code path)"

# ============================================================================
echo "== (n) --publish: emits the digest as a shareable, point-in-time snapshot; digest.md unaffected =="
RN="$(new_repo)"
seed_job "$RN" done "publish-item" >/dev/null
outN="$( cd "$RN" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$BUILD" --publish )"; rcN=$?
DIGN="$RN/.supervisor/handoff/digest.md"
SNAPN="$RN/.supervisor/handoff/snapshot.md"
[ "$rcN" -eq 0 ] && ok "exits 0 with --publish" || no "expected exit 0, got $rcN"
[ -f "$DIGN" ] && ok "digest.md still written with --publish" || no "digest.md missing with --publish"
[ -f "$SNAPN" ] && ok "AC-handoff-publish: snapshot.md written with --publish" || no "snapshot.md missing with --publish"
echo "$outN" | grep -qF "published snapshot" && ok "echoes the snapshot path" || no "no 'published snapshot' echo"
# Snapshot states it is a static export: generation time + explicit non-live/non-polling language.
grep -q "STATIC SNAPSHOT" "$SNAPN" 2>/dev/null && ok "snapshot states it is a static export" || no "snapshot missing static-export framing"
grep -qi "does not poll" "$SNAPN" 2>/dev/null && ok "snapshot states it does not poll" || no "snapshot missing 'does not poll' statement"
grep -qF "as-of HEAD" "$SNAPN" 2>/dev/null && ok "snapshot carries provenance (as-of HEAD)" || no "snapshot missing HEAD provenance"
# Snapshot carries the same work item (what shipped/decided/tried/state/provenance) as the digest.
grep -qF "publish-item" "$SNAPN" 2>/dev/null && ok "snapshot carries the work item (what shipped)" || no "snapshot missing work item content"
grep -qF "ship the publish-item thing" "$SNAPN" 2>/dev/null && ok "snapshot carries the Why/decision facet" || no "snapshot missing decision facet"
# digest.md content is UNCHANGED by publishing — re-run on the SAME repo/SAME job file with no flag
# (same mtime, so the only legitimately-volatile field is the `_Generated <ts>` wall-clock line, which
# is stripped before comparing). Reusing the same fixture (rather than a second freshly-seeded repo)
# avoids conflating this assertion with unrelated mtime-driven freshness-line drift between two repos.
DIGN_PUBLISH_COPY="$RN/.digest.after-publish.md"
cp "$DIGN" "$DIGN_PUBLISH_COPY" 2>/dev/null
run_build "$RN" >/dev/null   # re-run WITHOUT --publish, same repo, same job file
DIGN_FILT="$RN/.digest.filtered.publish.md"; DIGN2_FILT="$RN/.digest.filtered.noflag.md"
grep -v '^_Generated ' "$DIGN_PUBLISH_COPY" > "$DIGN_FILT"
grep -v '^_Generated ' "$DIGN"              > "$DIGN2_FILT"
if diff -q "$DIGN_FILT" "$DIGN2_FILT" >/dev/null 2>&1; then
  ok "digest.md is byte-identical whether or not --publish was passed (excluding the volatile generation timestamp)"
else
  no "digest.md differs when --publish is passed: $(diff "$DIGN2_FILT" "$DIGN_FILT" 2>&1 | head -5)"
fi

# ============================================================================
echo "== (o) AC-no-writes: --publish writes ONLY under .supervisor/handoff/; source-of-truth surfaces untouched =="
RO="$(new_repo)"
JOBO="$(seed_job "$RO" done "readonly-publish-job")"
seed_auto "$RO" "sess-o" >/dev/null
mkdir -p "$RO/.agent/rules" "$RO/.supervisor/postmortem"
RULEO="$RO/.agent/rules/process.json"; printf '[{"id":"r1"}]\n' > "$RULEO"
PMO="$RO/.supervisor/postmortem/results.jsonl"; printf '{"a":1}\n' > "$PMO"
job_ob="$(csum "$JOBO")"; rule_ob="$(csum "$RULEO")"; pm_ob="$(csum "$PMO")"
INV_O_BEFORE="$(mktmp)/inv.before"; mkdir -p "$(dirname "$INV_O_BEFORE")"
( cd "$RO" && find .supervisor .agent -type f 2>/dev/null | sort ) > "$INV_O_BEFORE"
( cd "$RO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$BUILD" --publish ) >/dev/null; rcO=$?
[ "$rcO" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rcO"
[ "$job_ob"  = "$(csum "$JOBO")" ]  && ok "job brief byte-identical after --publish" || no "job brief was modified"
[ "$rule_ob" = "$(csum "$RULEO")" ] && ok ".agent/rules/ byte-identical after --publish" || no ".agent/rules/ was modified"
[ "$pm_ob"   = "$(csum "$PMO")" ]   && ok "postmortem ledger byte-identical after --publish" || no "postmortem ledger was modified"
INV_O_AFTER="$(mktmp)/inv.after"; mkdir -p "$(dirname "$INV_O_AFTER")"
( cd "$RO" && find .supervisor .agent -type f 2>/dev/null | sort ) > "$INV_O_AFTER"
strayO=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    .supervisor/handoff/*) ;;                                   # sanctioned: digest.md + snapshot.md
    .supervisor/logs/memory.log|.supervisor/logs/twin.log) ;;   # sanctioned: reused readers' diagnostics
    *) grep -qxF "$p" "$INV_O_BEFORE" || { strayO=$((strayO+1)); echo "    stray new path: $p"; } ;;
  esac
done < "$INV_O_AFTER"
[ "$strayO" -eq 0 ] && ok "the one permitted write set is .supervisor/handoff/{digest.md,snapshot.md} — no stray writes" \
  || no "$strayO stray new path(s) outside the sanctioned .supervisor/handoff/ set"
# Anti-vacuity: prove the exercise actually ran (else the containment check above would pass on nothing having happened).
[ -f "$RO/.supervisor/handoff/snapshot.md" ] && [ -s "$RO/.supervisor/handoff/snapshot.md" ] \
  && ok "anti-vacuity: snapshot.md was actually produced and is non-empty" \
  || no "anti-vacuity FAILED: snapshot.md missing/empty — the containment check above would be vacuous"

# ============================================================================
echo "== (p) agent/command mirror: commands/handoff.md documents --publish in the same commit =="
HANDOFF_MD="$(dirname "$HERE")/commands/handoff.md"
[ -f "$HANDOFF_MD" ] && ok "commands/handoff.md exists" || no "commands/handoff.md missing at $HANDOFF_MD"
grep -qF -- "--publish" "$HANDOFF_MD" 2>/dev/null \
  && ok "commands/handoff.md documents the --publish flag" || no "commands/handoff.md does NOT mention --publish (mirror drift)"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
