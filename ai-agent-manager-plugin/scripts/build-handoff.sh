#!/usr/bin/env bash
# build-handoff.sh — deterministic, READ-ONLY "catch up / hand off in 2 minutes" digest assembler.
#
# Assembles ONE mode-agnostic digest from the plugin's continuity surfaces and writes it to
# .supervisor/handoff/digest.md (gitignored), then echoes the path — mirroring /insights
# (build-insights.sh). The digest is the human-curation layer ABOVE the existing read-* helpers:
# where it needs verified memory / lessons it CALLS the readers (read-project-memory.sh,
# read-lessons.sh) rather than re-parsing those stores.
#
# MODE-AGNOSTIC (AC2): ONE unified newest-first work-item list interleaving Supervisor jobs
# (.supervisor/jobs/{pending,in-progress,done,failed}/*.md), autonomous runs
# (.supervisor/autonomous/<session_id>/) and automate runs (.supervisor/automate/<run>.md) —
# NOT three per-mode digests.
#
# FIVE FACETS per item where derivable (AC3): decision · why · tried/rejected · current state ·
# provenance (the source artifact path it was drawn from). A facet that isn't derivable is OMITTED
# (never fabricated).
#
# FRESHNESS / basis (AC4 — mtime and SHA are NEVER conflated):
#   (a) ONLY when an artifact records an ACTUAL commit SHA in a STRUCTURED trailer
#       (`- **built_at_commit:** <sha>` / `- **basis_sha:** <sha>` / `- **commit_sha:** <sha>` /
#       `- **head_sha:** <sha>`) is that SHA compared to current HEAD. Match ⇒ fresh; mismatch ⇒
#       emit-WITH-a-hint showing BOTH SHAs (`hint — basis <sha>, HEAD <sha>`). Stale is never
#       silently dropped (mirrors read-bridge.sh). A branch name or PR URL is NEVER a commit basis.
#   (b) OTHERWISE (the common case — jobs/logs/worker-summaries/state.md carry no structured SHA)
#       basis = the artifact's mtime, freshness = unknown, rendered as a plain advisory WITHOUT
#       any SHA comparison.
#
# FAIL-SAFE / read-only (AC6, AC7): ALWAYS exits 0. Its OWN output is confined to
# .supervisor/handoff/. It NEVER modifies any source-of-truth surface. The only filesystem effect
# outside .supervisor/handoff/ is the reused read-* helpers' OWN pre-existing advisory diagnostics
# to .supervisor/logs/{memory,twin}.log (sanctioned — not suppressed). Absent surfaces (e.g.
# .supervisor/automate/ which does not exist on this repo today) silently skip. With NO continuity
# surfaces at all, a benign "nothing to summarize yet" line is emitted and exit 0.
#
# Usage:  build-handoff.sh
# Exit:   0 always — a digest tool must never break its caller. Prints the output path.

set -uo pipefail

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

# jq powers the autonomous state.json / session_end parsing. Mirror build-insights.sh: absent ⇒
# skip-but-exit-0 (the readers below are independently jq-guarded inside themselves).
command -v jq >/dev/null 2>&1 || { echo "build-handoff: jq required — skipping" >&2; exit 0; }

# Locate sibling read-* helpers robustly at runtime AND under the test harness (AC5).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
HELPERS_DIR="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR}"

OUT_DIR=".supervisor/handoff"
OUT="$OUT_DIR/digest.md"
MAX_ITEMS="${HANDOFF_MAX_ITEMS:-8}"
ts_now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
head_short="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

shopt -s nullglob

# ---- helpers ----------------------------------------------------------------

# Portable mtime → epoch seconds (GNU stat, then BSD/macOS stat). Empty on failure.
mtime_epoch() {
  local f="$1" e=""
  e="$(stat -c %Y "$f" 2>/dev/null || true)"
  [ -n "$e" ] || e="$(stat -f %m "$f" 2>/dev/null || true)"
  printf '%s' "$e"
}
# Epoch → human ISO date (UTC). Empty on failure.
epoch_iso() {
  local e="$1"
  [ -n "$e" ] || { printf 'unknown'; return; }
  date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || printf 'unknown'
}

# Extract the value of a STRUCTURED single-field markdown line `- **<key>:** <val>` from a file.
# Used for facet extraction AND the AC4(a) structured-SHA detection. Returns the FIRST match,
# trimmed. Never errors (tolerant of a malformed/absent file under set -u/pipefail).
md_field() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  sed -nE "s/^[[:space:]]*-[[:space:]]*\*\*${key}:?\*\*[[:space:]]*//p" "$file" 2>/dev/null | head -1
}

# Render the freshness/basis line for an artifact (AC4). Echoes a single advisory string.
#   $1 = file path (for mtime fallback)   $2 = a structured SHA if the artifact carried one (may be "")
# A branch name / PR URL is NEVER passed here — only a real commit SHA from a structured trailer.
freshness_line() {
  local file="$1" basis_sha="$2"
  if [ -n "$basis_sha" ] && [ -n "$head_sha" ]; then
    # (a) ACTUAL SHA → compare to HEAD. mtime is NOT consulted in this branch.
    if [ "$basis_sha" = "$head_sha" ]; then
      printf 'fresh (basis %s == HEAD)' "${basis_sha:0:8}"
    else
      printf 'hint — basis %s, HEAD %s' "${basis_sha:0:8}" "${head_sha:0:8}"
    fi
  else
    # (b) common case → mtime basis, freshness unknown. NO SHA comparison.
    local e iso
    e="$(mtime_epoch "$file")"; iso="$(epoch_iso "$e")"
    printf 'basis mtime %s · freshness unknown (no commit SHA recorded)' "$iso"
  fi
}

# Emit one work-item section to stdout. Args are pre-derived facets (any may be empty → omitted).
#   $1 title  $2 kind  $3 status(current state)  $4 decision  $5 why  $6 tried/rejected
#   $7 freshness  $8 provenance(path)  $9 extra-bullet (optional, pre-formatted markdown line)
emit_item() {
  local title="$1" kind="$2" state="$3" decision="$4" why="$5" tried="$6" fresh="$7" prov="$8" extra="${9:-}"
  echo "### $title"
  echo "_${kind}_"
  echo
  [ -n "$decision" ] && echo "- **Decision:** $decision"
  [ -n "$why" ]      && echo "- **Why:** $why"
  [ -n "$tried" ]    && echo "- **Tried / rejected:** $tried"
  [ -n "$state" ]    && echo "- **Current state:** $state"
  [ -n "$extra" ]    && echo "$extra"
  [ -n "$fresh" ]    && echo "- **Freshness / basis:** $fresh"
  [ -n "$prov" ]     && echo "- **Provenance:** \`$prov\`"
  echo
}

# ---- 1) Collect work items across ALL modes into a sortable index ----------
# Each index line: <epoch>\t<TYPE>\t<path>   (TYPE ∈ JOB:<lifecycle> | AUTO | AUTOMATE)
# We sort newest-first by mtime epoch and cap to MAX_ITEMS. Using a temp index keeps the
# interleave/merge (AC2) mode-agnostic and avoids per-mode sub-lists.
index="$(mktemp)"; body="$(mktemp)"
trap 'rm -f "$index" "$body" 2>/dev/null' EXIT

surfaces_found=0

# Supervisor jobs across all four lifecycle dirs.
for lc in in-progress pending failed done; do
  for f in ".supervisor/jobs/$lc"/*.md; do
    [ -f "$f" ] || continue
    surfaces_found=1
    e="$(mtime_epoch "$f")"; e="${e:-0}"
    printf '%s\t%s\t%s\n' "$e" "JOB:$lc" "$f" >> "$index"
  done
done

# Autonomous runs (one item per session dir; key off state.json when present, else the dir).
for d in .supervisor/autonomous/*/; do
  [ -d "$d" ] || continue
  surfaces_found=1
  anchor="$d"
  [ -f "${d}state.json" ] && anchor="${d}state.json"
  e="$(mtime_epoch "$anchor")"; e="${e:-0}"
  printf '%s\t%s\t%s\n' "$e" "AUTO" "$d" >> "$index"
done

# Automate runs — does NOT exist on this repo today; nullglob makes this a clean no-op (AC6).
for f in .supervisor/automate/*.md; do
  [ -f "$f" ] || continue
  surfaces_found=1
  e="$(mtime_epoch "$f")"; e="${e:-0}"
  printf '%s\t%s\t%s\n' "$e" "AUTOMATE" "$f" >> "$index"
done

# ---- 2) Render the newest-first, capped, interleaved item list into $body --
item_count=0
if [ -s "$index" ]; then
  # sort by epoch desc (numeric), stable, then take the top MAX_ITEMS.
  while IFS="$(printf '\t')" read -r epoch typ path; do
    [ -n "$path" ] || continue
    [ "$item_count" -ge "$MAX_ITEMS" ] && break
    item_count=$((item_count+1))

    case "$typ" in
      JOB:*)
        lc="${typ#JOB:}"
        title="$(basename "$path" .md)"
        # Facet extraction — all tolerant of absence (md_field returns empty → facet omitted).
        goal="$(md_field "$path" 'Goal')"
        [ -n "$goal" ] || goal="$(awk '/^\*\*Goal:\*\*/{sub(/^\*\*Goal:\*\*[[:space:]]*/,"");print;exit}' "$path" 2>/dev/null)"
        outcome="$(md_field "$path" 'outcome')"
        heal="$(md_field "$path" 'heal_decision')"
        heal_it="$(md_field "$path" 'heal_iterations')"
        pr="$(md_field "$path" 'PR')"
        # AC4(a): ONLY a STRUCTURED commit-SHA trailer is a basis. PR URL / feature_branch are NOT.
        basis_sha="$(md_field "$path" 'built_at_commit')"
        [ -n "$basis_sha" ] || basis_sha="$(md_field "$path" 'basis_sha')"
        [ -n "$basis_sha" ] || basis_sha="$(md_field "$path" 'commit_sha')"
        [ -n "$basis_sha" ] || basis_sha="$(md_field "$path" 'head_sha')"
        # Keep only a plausible hex SHA (7–40 hex). Anything else (e.g. a stray word) is discarded
        # so we NEVER fabricate/compare a non-SHA basis (AC4).
        case "$basis_sha" in
          *[!0-9a-fA-F]*|"") basis_sha="" ;;
          *) [ "${#basis_sha}" -ge 7 ] && [ "${#basis_sha}" -le 40 ] || basis_sha="" ;;
        esac

        # Five facets:
        decision="Supervisor job ($lc)$( [ -n "$outcome" ] && printf ' — outcome: %s' "$outcome" )"
        why="$goal"
        tried=""
        [ -n "$heal" ] && tried="self-heal $heal$( [ -n "$heal_it" ] && printf ' (%s)' "$heal_it" )"
        state="lifecycle: $lc"
        extra=""
        [ -n "$pr" ] && extra="- **PR:** $pr"
        fresh="$(freshness_line "$path" "$basis_sha")"
        emit_item "$title" "Supervisor job · $lc" "$state" "$decision" "$why" "$tried" "$fresh" "$path" "$extra" >> "$body"
        ;;

      AUTO)
        sj="${path}state.json"
        title="$(basename "${path%/}")"
        if [ -f "$sj" ]; then
          # Pull the newest iteration's facets via jq (tolerant — malformed JSON ⇒ empty fields).
          decision="$(jq -r '"autonomous run (\(.mode // "?") mode, iter \(.iteration // "?")/\(.max_iterations // "?"))"' "$sj" 2>/dev/null || true)"
          why="$(jq -r '(.iterations | last | .summary) // empty' "$sj" 2>/dev/null || true)"
          [ -n "$why" ] || why="$(jq -r '.requirement_path // empty' "$sj" 2>/dev/null || true)"
          last_status="$(jq -r '(.iterations | last | .supervisor_status) // empty' "$sj" 2>/dev/null || true)"
          last_heal="$(jq -r '(.iterations | last | .heal_decision) // empty' "$sj" 2>/dev/null || true)"
          last_pr="$(jq -r '(.iterations | last | .pr_url) // empty' "$sj" 2>/dev/null || true)"
          ended="$(jq -r '.ended_at // empty' "$sj" 2>/dev/null || true)"
          state="status: ${last_status:-unknown}$( [ -n "$ended" ] && printf ' (ended %s)' "$ended" )"
          tried=""
          [ -n "$last_heal" ] && tried="self-heal $last_heal"
          extra=""
          [ -n "$last_pr" ] && extra="- **PR:** $last_pr"
          prov="$sj"
        else
          decision="autonomous run"
          why=""; state="(no state.json — directory only)"; tried=""; extra=""; prov="$path"
        fi
        # AC4(b): autonomous state.json carries branch/pr_url but NO commit SHA → mtime basis.
        fresh="$(freshness_line "${sj:-$path}" "")"
        emit_item "$title" "Autonomous run" "$state" "$decision" "$why" "$tried" "$fresh" "$prov" "$extra" >> "$body"
        ;;

      AUTOMATE)
        title="$(basename "$path" .md)"
        goal="$(md_field "$path" 'Goal')"
        outcome="$(md_field "$path" 'outcome')"
        basis_sha="$(md_field "$path" 'built_at_commit')"
        [ -n "$basis_sha" ] || basis_sha="$(md_field "$path" 'commit_sha')"
        case "$basis_sha" in
          *[!0-9a-fA-F]*|"") basis_sha="" ;;
          *) [ "${#basis_sha}" -ge 7 ] && [ "${#basis_sha}" -le 40 ] || basis_sha="" ;;
        esac
        decision="automate run$( [ -n "$outcome" ] && printf ' — outcome: %s' "$outcome" )"
        fresh="$(freshness_line "$path" "$basis_sha")"
        emit_item "$title" "Automate run" "" "$decision" "$goal" "" "$fresh" "$path" "" >> "$body"
        ;;
    esac
  done < <(sort -t "$(printf '\t')" -k1,1nr "$index" 2>/dev/null)
fi

# ---- 3) Session state.md snapshot (current active session, if any) ----------
state_block=""
if [ -f ".supervisor/state.md" ]; then
  surfaces_found=1
  sess_id="$(md_field .supervisor/state.md 'session_id')"
  [ -n "$sess_id" ] || sess_id="$(sed -nE 's/^- session_id:[[:space:]]*//p' .supervisor/state.md 2>/dev/null | head -1)"
  sess_status="$(sed -nE 's/^- status:[[:space:]]*//p' .supervisor/state.md 2>/dev/null | head -1)"
  sess_phase="$(sed -nE 's/^- phase:[[:space:]]*//p' .supervisor/state.md 2>/dev/null | head -1)"
  sess_branch="$(sed -nE 's/^- branch:[[:space:]]*//p' .supervisor/state.md 2>/dev/null | head -1)"
  e="$(mtime_epoch .supervisor/state.md)"; iso="$(epoch_iso "$e")"
  {
    echo "## Active session (\`.supervisor/state.md\`)"
    echo
    [ -n "$sess_id" ]     && echo "- **Session:** $sess_id"
    [ -n "$sess_status" ] && echo "- **Status:** $sess_status"
    [ -n "$sess_phase" ]  && echo "- **Phase:** $sess_phase"
    [ -n "$sess_branch" ] && echo "- **Branch:** $sess_branch"
    # state.md carries NO commit SHA → mtime basis / unknown freshness (AC4b).
    echo "- **Freshness / basis:** basis mtime $iso · freshness unknown (no commit SHA recorded)"
    echo
  } > "$body.state"
  state_block="$body.state"
fi

# ---- 4) Verified memory / lessons appendix — via the READERS (AC5) ----------
# Reuse the sanctioned readers rather than re-parsing PROJECT_MEMORY.md / LESSONS.md. Each call is
# guarded: a missing/failing reader is a SILENT skip and never breaks exit 0 (AC5/AC7). The readers
# own their advisory diagnostics to .supervisor/logs/{memory}.log — that is sanctioned (AC7).
mem_out=""; les_out=""
if [ -f "$HELPERS_DIR/read-project-memory.sh" ]; then
  mem_out="$(bash "$HELPERS_DIR/read-project-memory.sh" 2>/dev/null || true)"
fi
if [ -f "$HELPERS_DIR/read-lessons.sh" ]; then
  les_out="$(bash "$HELPERS_DIR/read-lessons.sh" 2>/dev/null || true)"
fi

# ---- 5) Assemble the digest -------------------------------------------------
mkdir -p "$OUT_DIR" 2>/dev/null || { echo "build-handoff: cannot create $OUT_DIR — skipping" >&2; exit 0; }

{
  echo "# Handoff digest — catch up in 2 minutes"
  echo
  echo "_Generated $ts_now · as-of HEAD \`$head_short\` · READ-ONLY, advisory (subordinate to CLAUDE.md). Regenerate any time with this script._"
  echo

  if [ "$surfaces_found" -eq 0 ]; then
    # AC6: no continuity surfaces at all → benign line, exit 0.
    echo "_Nothing to summarize yet — no Supervisor jobs, autonomous/automate runs, or session state found under \`.supervisor/\`. Run \`/supervisor\`, \`/autonomous\`, or \`/automate\` first._"
  else
    [ -n "$state_block" ] && cat "$state_block"

    echo "## Recent work items (newest first, mode-agnostic — top $MAX_ITEMS)"
    echo
    echo "_One unified view across Supervisor jobs, autonomous runs, and automate runs. Each item shows the five facets where derivable (decision · why · tried/rejected · current state · provenance) plus a freshness/basis line. mtime and commit-SHA are never conflated: a SHA basis appears ONLY when an artifact recorded one in a structured trailer._"
    echo
    if [ "$item_count" -gt 0 ]; then
      cat "$body"
    else
      echo "_No work items found across job / autonomous / automate surfaces yet._"
      echo
    fi

    # Appendix — verified memory / lessons (only when a reader emitted substantive content).
    # The readers always print a banner line; treat banner-only output as "nothing to show".
    if [ -n "$mem_out" ] || [ -n "$les_out" ]; then
      echo "## Appendix — verified project memory & lessons"
      echo
      echo "_Sourced via the sanctioned readers (\`read-project-memory.sh\`, \`read-lessons.sh\`) — provenance-verified, advisory. NOT re-parsed here._"
      echo
      if [ -n "$mem_out" ]; then
        echo "<details><summary>Project memory</summary>"
        echo
        printf '%s\n' "$mem_out"
        echo
        echo "</details>"
        echo
      fi
      if [ -n "$les_out" ]; then
        echo "<details><summary>Lessons</summary>"
        echo
        printf '%s\n' "$les_out"
        echo
        echo "</details>"
        echo
      fi
    fi
  fi
} > "$OUT"

rm -f "$body.state" 2>/dev/null || true

echo "build-handoff: wrote $OUT ($item_count work item(s), as-of HEAD $head_short)"
exit 0
