#!/usr/bin/env bash
# test-build-vault.sh — self-tests for build-vault.sh, the read-only Obsidian "Full Linked
# Vault" projection (v14.10.0+). Runs in isolated temp git repos via mktemp -d and writes to
# isolated temp vault dirs (NEVER touches the real .supervisor/ or any real Obsidian vault).
# Mirrors test-system-contract.sh convention. Exit 0 = all pass, 1 = any failure.
#
# Covers the acceptance criteria:
#   1. env-unset → no-op (no vault written, exit 0)
#   2. any source absent → still a VALID vault + exit 0 (LOAD-BEARING); two variants:
#        2a. twin + LESSONS absent but logs + PROJECT_MEMORY present
#        2b. maximally-sparse repo (effectively no sources) → still valid vault
#   3. idempotent — second run on unchanged sources writes ZERO notes
#   4. per-project isolation — a sibling project's folder is byte-for-byte untouched
#   5. writes only under dest — source .supervisor/ files unchanged; nothing written
#      under $VAULT outside $VAULT/<slug>/

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HERE/build-vault.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# All temp dirs live under ONE root so a single trap reliably cleans everything. (We can't grow
# an array inside `$(mktmp)` — command substitution runs in a subshell, so the parent never sees
# the append; using a single root sidesteps that entirely.)
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

# Populate a minimal session_end JSONL log under a repo.
seed_log() {
  local repo="$1" sid="${2:-sess-1}"
  mkdir -p "$repo/.supervisor/logs"
  printf '%s\n' '{"event":"session_end","ts":"2026-06-05T10:00:00Z","status":"completed","branch":"feature/x","pr_url":"https://example/pr/1","heal_decision":"PASS","subtasks_completed":2,"files_changed":3}' \
    > "$repo/.supervisor/logs/$sid.jsonl"
}

# Cross-platform mtime in seconds (BSD/macOS stat -f, GNU stat -c).
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# Checksum helper (matches build-vault's tool fallback).
csum() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1; fi
}

# Note: build-vault no-ops (exit 0, no vault) when jq is absent. Detect that so the "valid vault"
# assertions degrade to "exited 0, wrote nothing" instead of hard-failing on a jq-less box.
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1

echo "== 1. env-unset → no-op (nothing written, exit 0) =="
R1="$(new_repo)"
V1="$(mktmp)"      # a vault dir that exists but must NOT be written into
( cd "$R1" && env -u AI_AGENT_MANAGER_OBSIDIAN_VAULT -u AI_AGENT_MANAGER_OBSIDIAN_SLUG bash "$BUILD" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0 with no vault configured" || no "expected exit 0, got $rc"
# Nothing should have been created anywhere under the (unrelated) vault dir.
created="$(find "$V1" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
[ "${created:-0}" -eq 0 ] && ok "no vault written when destination unset" || no "files appeared despite unset vault ($created)"

echo "== 2a. sparse: twin + LESSONS absent, logs + memory present → valid vault, exit 0 =="
R2="$(new_repo)"
V2="$(mktmp)"
SLUG2="$(basename "$R2")"
seed_log "$R2" "sess-a"
mkdir -p "$R2/.supervisor/memory"
printf '# Project Memory\n\n- a durable fact\n' > "$R2/.supervisor/memory/PROJECT_MEMORY.md"
# Deliberately NO .supervisor/twin/ and NO .supervisor/memory/LESSONS.md
( cd "$R2" && AI_AGENT_MANAGER_OBSIDIAN_VAULT="$V2" bash "$BUILD" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0 with twin+LESSONS absent" || no "expected exit 0, got $rc"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ -f "$V2/$SLUG2/$SLUG2 — Index.md" ] && ok "valid vault produced (index/MOC note exists)" || no "index note missing under \$VAULT/<slug>/"
  # Run note present (logs source), memory note present, no twin contracts section linkage.
  [ -f "$V2/$SLUG2/$SLUG2 — Project Memory.md" ] && ok "project-memory note projected" || no "project-memory note missing"
  ls "$V2/$SLUG2/$SLUG2 — Run — "*.md >/dev/null 2>&1 && ok "run note projected from logs" || no "run note missing"
else
  created="$(find "$V2" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
  [ "${created:-0}" -eq 0 ] && ok "jq absent → clean no-op (no vault), exit 0" || no "jq absent but vault written"
fi

echo "== 2b. maximally-sparse repo (effectively no sources) → still valid vault, exit 0 =="
R3="$(new_repo)"
V3="$(mktmp)"
SLUG3="$(basename "$R3")"
# No .supervisor/ at all beyond the bare repo.
( cd "$R3" && AI_AGENT_MANAGER_OBSIDIAN_VAULT="$V3" bash "$BUILD" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0 with no sources at all" || no "expected exit 0, got $rc"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ -f "$V3/$SLUG3/$SLUG3 — Index.md" ] && ok "valid (near-empty) vault produced (index note exists)" || no "index note missing for sparse repo"
  grep -q "No session runs recorded yet" "$V3/$SLUG3/$SLUG3 — Index.md" 2>/dev/null \
    && ok "index degrades gracefully (empty-runs placeholder)" || no "index missing empty-source placeholder"
else
  created="$(find "$V3" -mindepth 1 2>/dev/null | wc -l | tr -d ' ')"
  [ "${created:-0}" -eq 0 ] && ok "jq absent → clean no-op (no vault), exit 0" || no "jq absent but vault written"
fi

echo "== 3. idempotent (no rewrite on unchanged sources) =="
R4="$(new_repo)"
V4="$(mktmp)"
SLUG4="$(basename "$R4")"
seed_log "$R4" "sess-i"
mkdir -p "$R4/.supervisor/memory"
printf '# Project Memory\n\n- stable fact\n' > "$R4/.supervisor/memory/PROJECT_MEMORY.md"
( cd "$R4" && AI_AGENT_MANAGER_OBSIDIAN_VAULT="$V4" bash "$BUILD" ) >/dev/null 2>&1
out2="$( cd "$R4" && AI_AGENT_MANAGER_OBSIDIAN_VAULT="$V4" bash "$BUILD" 2>/dev/null )"
rc=$?
if [ "$HAVE_JQ" -eq 1 ]; then
  [ -f "$V4/$SLUG4/$SLUG4 — Index.md" ] || no "first run produced no vault (idempotency precondition)"
  # Primary signal: the script's own summary on the 2nd run reports 0 written.
  if echo "$out2" | grep -Eq 'build-vault: 0 note\(s\) written'; then
    ok "second run writes ZERO notes (summary: 0 written)"
  else
    no "second run reported writes: $(echo "$out2" | grep 'note(s) written' || echo '<no summary>')"
  fi
  # Corroborate via mtimes: snapshot each note's mtime, do a fresh re-run on unchanged sources,
  # and assert no note file's mtime changed. Uses a temp snapshot file (no associative arrays —
  # macOS ships bash 3.2, which lacks `declare -A`).
  changed=0
  SNAP="$(mktmp)/mtimes"; mkdir -p "$(dirname "$SNAP")"; : > "$SNAP"
  for nf in "$V4/$SLUG4/"*.md; do
    [ -f "$nf" ] || continue
    printf '%s\t%s\n' "$(mtime "$nf")" "$nf" >> "$SNAP"
  done
  ( cd "$R4" && AI_AGENT_MANAGER_OBSIDIAN_VAULT="$V4" bash "$BUILD" ) >/dev/null 2>&1
  while IFS="$(printf '\t')" read -r m0 nf; do
    [ -n "$nf" ] && [ -f "$nf" ] || continue
    [ "$m0" = "$(mtime "$nf")" ] || changed=$((changed+1))
  done < "$SNAP"
  [ "$changed" -eq 0 ] && ok "note mtimes unchanged across an unchanged re-run" || no "$changed note(s) rewritten on unchanged re-run"
else
  ok "jq absent → idempotency vacuously holds (no-op)"
  ok "jq absent → mtimes trivially unchanged (no-op)"
fi

echo "== 4. per-project isolation (sibling folder untouched) =="
R5="$(new_repo)"
V5="$(mktmp)"
SLUG5="$(basename "$R5")"
seed_log "$R5" "sess-iso"
# Pre-create a SIBLING project's folder with a sentinel of known content.
mkdir -p "$V5/other-project"
printf 'SENTINEL CONTENT — do not touch\n' > "$V5/other-project/sentinel.md"
sent_before="$(csum "$V5/other-project/sentinel.md")"
( cd "$R5" && AI_AGENT_MANAGER_OBSIDIAN_VAULT="$V5" bash "$BUILD" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0 with a sibling project present" || no "expected exit 0, got $rc"
sent_after="$(csum "$V5/other-project/sentinel.md")"
[ -f "$V5/other-project/sentinel.md" ] && [ "$sent_before" = "$sent_after" ] \
  && ok "sibling project's sentinel byte-for-byte unchanged" || no "sibling project's file was modified"
if [ "$HAVE_JQ" -eq 1 ]; then
  # And the run actually wrote into ITS OWN slug folder (proving the run did something, not just no-op'd).
  [ -d "$V5/$SLUG5" ] && [ "$SLUG5" != "other-project" ] \
    && ok "run wrote only into its own slug folder ($SLUG5)" || no "run did not write its own slug folder"
fi

echo "== 5. writes only under dest (sources unchanged; nothing outside <slug>/) =="
R6="$(new_repo)"
V6="$(mktmp)"
SLUG6="$(basename "$R6")"
seed_log "$R6" "sess-dest"
mkdir -p "$R6/.supervisor/memory"
printf '# Project Memory\n\n- immutable source\n' > "$R6/.supervisor/memory/PROJECT_MEMORY.md"
mem_before="$(csum "$R6/.supervisor/memory/PROJECT_MEMORY.md")"
log_before="$(csum "$R6/.supervisor/logs/sess-dest.jsonl")"
( cd "$R6" && AI_AGENT_MANAGER_OBSIDIAN_VAULT="$V6" bash "$BUILD" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0" || no "expected exit 0, got $rc"
# Source-of-truth files must be untouched (read-only projection).
[ "$mem_before" = "$(csum "$R6/.supervisor/memory/PROJECT_MEMORY.md")" ] \
  && ok "source PROJECT_MEMORY.md unchanged (read-only)" || no "source PROJECT_MEMORY.md was modified"
[ "$log_before" = "$(csum "$R6/.supervisor/logs/sess-dest.jsonl")" ] \
  && ok "source session log unchanged (read-only)" || no "source session log was modified"
if [ "$HAVE_JQ" -eq 1 ]; then
  # Everything created under $VAULT must live under $VAULT/<slug>/ (no stray top-level files).
  stray="$(find "$V6" -mindepth 1 -maxdepth 1 ! -name "$SLUG6" 2>/dev/null | wc -l | tr -d ' ')"
  [ "${stray:-0}" -eq 0 ] && ok "no files written under \$VAULT outside <slug>/" || no "$stray stray entr(y/ies) under \$VAULT outside <slug>/"
else
  ok "jq absent → nothing written (sources trivially unchanged)"
  ok "jq absent → no stray files under \$VAULT (no-op)"
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
