#!/usr/bin/env bash
# build-vault.sh — project this repo's accumulated knowledge into an Obsidian-ready
# "Full Linked Vault" in a configurable, SHARED destination dir, so multiple projects
# can live side-by-side in one vault under per-project subfolders (v14.10.0+).
#
# This is a READ-ONLY DOWNSTREAM PROJECTION. It READS source artifacts from .supervisor/
# (logs, twin contracts, memory, lessons) and WRITES ONLY under $VAULT/<slug>/. It modifies
# ZERO source-of-truth files: no agent, no /insights, no build-insights.sh, no supervisor.md,
# no .supervisor/ source. The engine behaves identically with or without the vault, and no
# agent ever reads the vault back — it is a one-way projection for human/Obsidian consumption.
# No data leaves your machine: this only writes local markdown to a local directory you chose.
#
# OPT-IN: does NOTHING unless a vault destination is configured (env var or config file).
#
# IDEMPOTENT / STATELESS: each run FULLY re-derives $VAULT/<slug>/ from the current sources and
# writes a note ONLY when its content hash differs from the on-disk file (content-hash dedup,
# mirrored from write-system-contract.sh). The vault folder IS the ledger — there is no separate
# manifest/state file. Re-run with no source change => zero writes. The hashed body NEVER embeds
# a per-run timestamp, so the zero-writes guarantee holds.
#
# SPARSE-TOLERANT: with ANY source absent or empty (twin dir, LESSONS.md, logs, PROJECT_MEMORY.md)
# it still emits a VALID vault (the missing section omitted/near-empty) and ALWAYS exits 0.
#
# Config resolution (vault):  $LOOMWRIGHT_OBSIDIAN_VAULT > .supervisor/obsidian-config.json .vault
# Config resolution (slug):   $LOOMWRIGHT_OBSIDIAN_SLUG  > .supervisor/obsidian-config.json .slug > basename($GITROOT)
#
# Usage:  build-vault.sh
# Exit:   0 ALWAYS — a projection/reporting tool must never break its caller.

set -uo pipefail

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

# jq is required to parse the config file and the JSONL logs. Without it, degrade to a clean no-op.
command -v jq >/dev/null 2>&1 || { echo "build-vault: jq required — skipping (no vault written)" >&2; exit 0; }

CONFIG=".supervisor/obsidian-config.json"

# ---- A. Resolve the vault destination (opt-in) ----------------------------
VAULT="${LOOMWRIGHT_OBSIDIAN_VAULT:-}"
if [ -z "$VAULT" ] && [ -f "$CONFIG" ]; then
  # Tolerate a malformed/partial config: jq failure or null -> empty (treated as unset).
  VAULT="$(jq -r '.vault // empty' "$CONFIG" 2>/dev/null || true)"
fi

if [ -z "$VAULT" ]; then
  cat <<'EOF'
build-vault: no Obsidian vault destination configured — nothing written (this is a no-op).

To opt in, do ONE of:
  1. Set an environment variable to your vault path:
       export LOOMWRIGHT_OBSIDIAN_VAULT="$HOME/Obsidian/MyVault"
  2. Or create .supervisor/obsidian-config.json:
       { "vault": "/absolute/path/to/your/Obsidian/Vault", "slug": "optional-project-name" }

The vault is a SHARED, common destination — multiple projects write into per-project
subfolders under it. This script only ever writes under <vault>/<project-slug>/.
EOF
  exit 0
fi

# Expand a leading ~ (config files can't rely on shell tilde expansion).
case "$VAULT" in
  "~")   VAULT="$HOME" ;;
  "~/"*) VAULT="$HOME/${VAULT#~/}" ;;
esac

# ---- A. Resolve + sanitize the project slug -------------------------------
SLUG="${LOOMWRIGHT_OBSIDIAN_SLUG:-}"
if [ -z "$SLUG" ] && [ -f "$CONFIG" ]; then
  SLUG="$(jq -r '.slug // empty' "$CONFIG" 2>/dev/null || true)"
fi
[ -n "$SLUG" ] || SLUG="$(basename "$GITROOT" 2>/dev/null || echo project)"
# Sanitize to a filesystem-safe token: collapse path separators and anything not [A-Za-z0-9._-]
# into '-' (mirrors write-system-contract.sh's SAFE_ID approach), so the slug can NEVER escape
# its own subfolder (no '/', '..', etc.) — a hard guarantee that one project never touches another.
SLUG="$(printf '%s' "$SLUG" | tr '/' '-' | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
# The char class above keeps '.' and '-', so a pure-dot slug ('.', '..', '...') would SURVIVE and
# resolve to a path-escape (e.g. DEST="$VAULT/.." writes to the vault's PARENT). Neutralize that:
# strip any leading dots, then reject an empty-or-pure-dot result back to the safe fallback. This
# is what makes the "slug can NEVER escape its own subfolder" guarantee above actually hold.
SLUG="$(printf '%s' "$SLUG" | sed -E 's/^[.]+//')"
case "$SLUG" in
  ""|.|..|...*) SLUG="project" ;;
esac
[ -n "$SLUG" ] || SLUG="project"

# ---- A. Validate / create the per-project destination ---------------------
# We write ONLY under $VAULT/$SLUG/. We never create, modify, or delete anything in a sibling
# project's folder or anywhere else under $VAULT outside this subfolder.
DEST="$VAULT/$SLUG"
if ! mkdir -p "$DEST" 2>/dev/null; then
  echo "build-vault: cannot create vault destination '$DEST' — skipping (no vault written)" >&2
  exit 0
fi
if [ ! -w "$DEST" ]; then
  echo "build-vault: vault destination '$DEST' is not writable — skipping" >&2
  exit 0
fi

# ---- sha tool (fail-safe: no tool -> clean no-op) -------------------------
if   command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum    >/dev/null 2>&1; then sha() { shasum -a 256 | cut -d' ' -f1; }
else
  echo "build-vault: no sha256 tool (sha256sum/shasum) — dedup unavailable, skipping" >&2
  exit 0
fi

# ---- Counters + atomic, content-hash-deduped note writer ------------------
# write_note is invoked as the LAST element of a `{ ... } | write_note` pipe, which runs in a
# SUBSHELL in non-interactive bash (no `lastpipe`). Shell-variable updates there would be lost, so
# the writer records each outcome as a single char ('W'/'U'/'S') appended to a tally file; the
# parent counts from that file afterward. This is robust regardless of shell options.
TALLY="$(mktemp 2>/dev/null || echo "$DEST/.tally.$$")"
: > "$TALLY" 2>/dev/null || true
records=""   # set later (per-run section); pre-declared so the cleanup trap is safe under `set -u`
trap 'rm -f "$records" "$TALLY" 2>/dev/null' EXIT

# write_note <relative-name-under-DEST> ; body on stdin.
# Writes ONLY when the new body's content hash differs from the existing on-disk file.
# Atomic: materialize a temp file IN $DEST then `mv` (same-filesystem rename). The hashed body
# carries NO per-run timestamp, so identical sources => identical hash => zero writes.
write_note() {
  local rel="$1" target tmp newhash oldhash
  target="$DEST/$rel"
  tmp="$(mktemp "$DEST/.vtmp.XXXXXX" 2>/dev/null)" || { echo "build-vault: mktemp failed for $rel — skipping note" >&2; printf 'S' >> "$TALLY" 2>/dev/null; return 0; }
  cat > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; printf 'S' >> "$TALLY" 2>/dev/null; return 0; }
  newhash="$(cat "$tmp" | sha 2>/dev/null)"
  if [ -f "$target" ]; then
    oldhash="$(cat "$target" | sha 2>/dev/null)"
    if [ "$newhash" = "$oldhash" ]; then
      rm -f "$tmp" 2>/dev/null
      printf 'U' >> "$TALLY" 2>/dev/null
      return 0
    fi
  fi
  if mv "$tmp" "$target" 2>/dev/null; then
    printf 'W' >> "$TALLY" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
    printf 'S' >> "$TALLY" 2>/dev/null
    echo "build-vault: failed to write '$target' — skipping note" >&2
  fi
  return 0
}

# yaml_escape — make a scalar safe to place inside double-quoted YAML.
yaml_escape() { printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# ===========================================================================
# B/C. TWIN CONTRACT NOTES  (.supervisor/twin/contracts/*.md — LIKELY ABSENT)
# ===========================================================================
TWIN_DIR=".supervisor/twin/contracts"
declare -a CONTRACT_LINKS=()   # index links: [[<slug> — Contract — <id>]]
HAVE_CONTRACTS=0

shopt -s nullglob
contract_files=("$TWIN_DIR"/*.md)
if [ "${#contract_files[@]}" -gt 0 ]; then
  HAVE_CONTRACTS=1
  for cf in "${contract_files[@]}"; do
    [ -f "$cf" ] || continue
    cid="$(basename "$cf" .md)"
    note_name="$SLUG — Contract — $cid"
    CONTRACT_LINKS+=("$note_name")

    # Read the raw contract body (read-only). Tolerate an unreadable file -> empty body.
    body="$(cat "$cf" 2>/dev/null || true)"

    # Derive [[dependency]] wikilinks for Obsidian graph "blast radius". The contract body may be
    # JSON (then read .dependencies[] / .depends_on[]) or plain markdown — either way we degrade
    # gracefully to "no dependencies recorded" if nothing parseable is found.
    declare -a deps=()
    if printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
      while IFS= read -r d; do
        [ -n "$d" ] && deps+=("$d")
      done < <(printf '%s' "$body" | jq -r '
        ((.dependencies // .depends_on // []) | if type=="array" then .[] else empty end)
        | if type=="string" then . elif type=="object" then (.id // .name // empty) else empty end
      ' 2>/dev/null || true)
    fi

    {
      echo "---"
      echo "type: twin-contract"
      echo "project: \"$(yaml_escape "$SLUG")\""
      echo "subsystem: \"$(yaml_escape "$cid")\""
      if [ "${#deps[@]}" -gt 0 ]; then
        printf 'dependencies: ['
        sep=""
        for d in "${deps[@]}"; do printf '%s"%s"' "$sep" "$(yaml_escape "$d")"; sep=", "; done
        printf ']\n'
      fi
      echo "tags: [type/twin-contract, project/$SLUG]"
      echo "---"
      echo
      echo "# Contract — $cid"
      echo
      echo "_System Twin contract for subsystem \`$cid\` (advisory; subordinate to CLAUDE.md)._"
      echo
      if [ "${#deps[@]}" -gt 0 ]; then
        echo "## Depends on (blast radius)"
        for d in "${deps[@]}"; do
          dlink="$SLUG — Contract — $d"
          echo "- [[$dlink]]"
        done
        echo
      else
        echo "## Depends on (blast radius)"
        echo "_No dependencies recorded in this contract._"
        echo
      fi
      echo "## Contract body"
      echo '```'
      printf '%s\n' "$body"
      echo '```'
      echo
      echo "_Back to [[$SLUG — Index]]_"
    } | write_note "$note_name.md"
    unset deps
  done
fi

# ===========================================================================
# B/C. PER-RUN NOTES  (.supervisor/logs/*.jsonl session_end events)
# ===========================================================================
LOGS_DIR=".supervisor/logs"
declare -a RUN_LINKS=()
records="$(mktemp 2>/dev/null)" || records=""
# NOTE: the EXIT trap that cleans up both "$records" and "$TALLY" was already installed above
# (right after $TALLY was created). We deliberately do NOT re-install a trap here — a second
# `trap ... EXIT` would CLOBBER the combined cleanup and leak the tally file.

log_files=("$LOGS_DIR"/*.jsonl)
if [ -n "$records" ] && [ "${#log_files[@]}" -gt 0 ]; then
  for f in "${log_files[@]}"; do
    [ -f "$f" ] || continue
    sid="$(basename "$f" .jsonl)"
    # Take the LAST session_end event in the file (mirrors build-insights.sh). Flat System Twin
    # hard-signal fields default to null when older logs lack them.
    jq -c --arg sid "$sid" '
      select(.event=="session_end")
      | {sid:$sid, ts:(.ts//""), status:(.status//"unknown"), branch:(.branch//""),
         pr_url:(.pr_url//""), heal_decision:(.heal_decision//""),
         heal_iterations:(.heal_iterations//null), rubric_score:(.rubric_score//null),
         subtasks_completed:(.subtasks_completed//null), files_changed:(.files_changed//null),
         duration_seconds:(.duration_seconds//null),
         contract_conformance_status:(.contract_conformance_status//null),
         contract_violations:(.contract_violations//null),
         benchmark_status:(.benchmark_status//null),
         benchmark_metric:(.benchmark_metric//null),
         benchmark_value:(.benchmark_value//null),
         benchmark_delta:(.benchmark_delta//null)}
    ' "$f" 2>/dev/null | tail -1 >> "$records" 2>/dev/null || true
  done
fi

run_count=0
if [ -n "$records" ] && [ -s "$records" ]; then
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    sid="$(printf '%s' "$r" | jq -r '.sid' 2>/dev/null || true)"
    [ -n "$sid" ] && [ "$sid" != "null" ] || continue
    note_name="$SLUG — Run — $sid"
    RUN_LINKS+=("$note_name")
    run_count=$((run_count + 1))

    # If a run reports twin contract conformance, cross-link it to the contract notes so Obsidian
    # graph shows run<->contract relationships (only when contract notes actually exist).
    {
      echo "---"
      printf '%s\n' "$r" | jq -r '
        "session_id: \(.sid)",
        (if .ts!="" then "created: \(.ts|split("T")[0])" else empty end),
        "status: \(.status)",
        (if .branch!=""         then "branch: \(.branch)"                   else empty end),
        (if .pr_url!=""          then "pr_url: \(.pr_url)"                   else empty end),
        (if .heal_decision!=""   then "heal_decision: \(.heal_decision)"    else empty end),
        (if .heal_iterations!=null    then "heal_iterations: \(.heal_iterations)"        else empty end),
        (if .rubric_score!=null       then "rubric_score: \"\(.rubric_score)\""          else empty end),
        (if .subtasks_completed!=null then "subtasks_completed: \(.subtasks_completed)" else empty end),
        (if .files_changed!=null      then "files_changed: \(.files_changed)"            else empty end),
        (if .duration_seconds!=null   then "duration_seconds: \(.duration_seconds)"      else empty end),
        (if .contract_conformance_status!=null then "contract_conformance_status: \(.contract_conformance_status)" else empty end),
        (if .contract_violations!=null then "contract_violations: \(.contract_violations)" else empty end),
        (if .benchmark_status!=null   then "benchmark_status: \(.benchmark_status)"      else empty end),
        (if .benchmark_metric!=null   then "benchmark_metric: \(.benchmark_metric)"      else empty end),
        (if .benchmark_value!=null    then "benchmark_value: \(.benchmark_value)"        else empty end),
        (if .benchmark_delta!=null    then "benchmark_delta: \(.benchmark_delta)"        else empty end)
      ' 2>/dev/null
      echo "project: \"$(yaml_escape "$SLUG")\""
      echo "tags: [type/session-log, project/$SLUG]"
      echo "---"
      echo
      echo "# Session $sid"
      echo
      printf '%s\n' "$r" | jq -r '
        "- **Status:** \(.status)",
        "- **Self-heal:** \(.heal_decision // "—") (\(.heal_iterations // "—") iterations)",
        "- **Rubric:** \(.rubric_score // "—")",
        "- **Subtasks completed:** \(.subtasks_completed // "—")",
        "- **Files changed:** \(.files_changed // "—")",
        (if .contract_conformance_status!=null
           then "- **Contract conformance:** \(.contract_conformance_status) (\(.contract_violations // 0) advisory violation(s))"
           else empty end),
        (if .benchmark_status!=null
           then "- **Benchmark:** \(.benchmark_status)\(if .benchmark_metric!=null then " — \(.benchmark_metric)" else "" end)\(if .benchmark_value!=null then "=\(.benchmark_value)" else "" end)\(if .benchmark_delta!=null then " (delta \(.benchmark_delta))" else "" end)"
           else empty end),
        (if .pr_url!="" then "- **PR:** \(.pr_url)" else empty end)
      ' 2>/dev/null
      echo
      # Cross-link runs -> contracts (best-effort): when this run reported conformance AND we wrote
      # contract notes, link to them so the graph view connects the run to the subsystems it touched.
      conf="$(printf '%s' "$r" | jq -r '.contract_conformance_status // empty' 2>/dev/null || true)"
      if [ "$HAVE_CONTRACTS" -eq 1 ] && [ -n "$conf" ]; then
        echo "## Related contracts"
        for cl in "${CONTRACT_LINKS[@]}"; do
          echo "- [[$cl]]"
        done
        echo
      fi
      echo "_Back to [[$SLUG — Index]]_"
    } | write_note "$note_name.md"
  done < "$records"
fi

# ===========================================================================
# B/C. PROJECT_MEMORY + LESSONS notes (omitted when source absent)
# ===========================================================================
HAVE_MEMORY=0
MEM_SRC=".supervisor/memory/PROJECT_MEMORY.md"
MEM_NOTE="$SLUG — Project Memory"
if [ -f "$MEM_SRC" ]; then
  HAVE_MEMORY=1
  {
    echo "---"
    echo "type: project-memory"
    echo "project: \"$(yaml_escape "$SLUG")\""
    echo "tags: [type/project-memory, project/$SLUG]"
    echo "---"
    echo
    echo "# Project Memory"
    echo
    echo "_Projected from \`$MEM_SRC\` (advisory — subordinate to CLAUDE.md)._"
    echo
    # DELIBERATE RAW PROJECTION: the Obsidian vault is a local, read-only personal projection, not a
    # trust boundary, so PROJECT_MEMORY is projected verbatim rather than routed through
    # read-project-memory.sh (its provenance gate). Routing memory through the read-side gate here is
    # a future follow-up; same decision is applied symmetrically to LESSONS below.
    cat "$MEM_SRC" 2>/dev/null || true
    echo
    echo "_Back to [[$SLUG — Index]]_"
  } | write_note "$MEM_NOTE.md"
fi

HAVE_LESSONS=0
LESSONS_SRC=".supervisor/memory/LESSONS.md"
LESSONS_NOTE="$SLUG — Lessons"
if [ -f "$LESSONS_SRC" ]; then
  HAVE_LESSONS=1
  {
    echo "---"
    echo "type: lessons"
    echo "project: \"$(yaml_escape "$SLUG")\""
    echo "tags: [type/lessons, project/$SLUG]"
    echo "---"
    echo
    echo "# Lessons"
    echo
    echo "_Projected from \`$LESSONS_SRC\` (advisory — subordinate to CLAUDE.md)._"
    echo
    # DELIBERATE RAW PROJECTION (symmetric with the PROJECT_MEMORY raw `cat` above): the Obsidian
    # vault is a local, read-only personal projection, not a trust boundary, so LESSONS is projected
    # verbatim rather than routed through read-lessons.sh (its provenance + stale gate). Routing both
    # memory files through their read-side gates here is a future follow-up; today they stay raw cats.
    cat "$LESSONS_SRC" 2>/dev/null || true
    echo
    echo "_Back to [[$SLUG — Index]]_"
  } | write_note "$LESSONS_NOTE.md"
fi

# ===========================================================================
# C. INDEX / MOC note — links every section + a Dataview live board
# ===========================================================================
# NOTE: the index intentionally does NOT embed a generated-at timestamp in its hashed body, so a
# no-source-change re-run leaves the index hash identical => zero writes (idempotency contract).
{
  echo "---"
  echo "type: project-index"
  echo "project: \"$(yaml_escape "$SLUG")\""
  echo "tags: [type/project-index, project/$SLUG]"
  echo "---"
  echo
  echo "# $SLUG — Index"
  echo
  echo "_Full Linked Vault projection of this project's accumulated knowledge. Plain markdown —"
  echo "readable anywhere; with Obsidian (and the **Dataview** plugin) it renders as a live, linked board._"
  echo

  echo "## Runs"
  if [ "${#RUN_LINKS[@]}" -gt 0 ]; then
    for rl in "${RUN_LINKS[@]}"; do echo "- [[$rl]]"; done
  else
    echo "_No session runs recorded yet._"
  fi
  echo

  echo "## Twin contracts"
  if [ "$HAVE_CONTRACTS" -eq 1 ] && [ "${#CONTRACT_LINKS[@]}" -gt 0 ]; then
    for cl in "${CONTRACT_LINKS[@]}"; do echo "- [[$cl]]"; done
  else
    echo "_No System Twin contracts yet (\`.supervisor/twin/contracts/\` is absent or empty)._"
  fi
  echo

  echo "## Memory & lessons"
  if [ "$HAVE_MEMORY" -eq 1 ]; then echo "- [[$MEM_NOTE]]"; fi
  if [ "$HAVE_LESSONS" -eq 1 ]; then echo "- [[$LESSONS_NOTE]]"; fi
  if [ "$HAVE_MEMORY" -eq 0 ] && [ "$HAVE_LESSONS" -eq 0 ]; then
    echo "_No project memory or lessons recorded yet._"
  fi
  echo

  echo "## Live board (Dataview)"
  echo "With the Dataview plugin installed, the runs in this project render as a sortable table:"
  echo '```dataview'
  echo "TABLE status, rubric_score, heal_decision, subtasks_completed, files_changed, pr_url"
  echo "FROM #project/$SLUG AND #type/session-log"
  echo "SORT created DESC"
  echo '```'
  echo
  echo "_This vault is a one-way projection: regenerate any time with \`build-vault.sh\`. No agent"
  echo "ever reads it back, and nothing here changes how the engine behaves._"
} | write_note "$SLUG — Index.md"

# ---- Summary --------------------------------------------------------------
# Counts come from the tally file (write_note runs in a pipe subshell, so it can't update shell
# vars in this scope — see the write_note comment). Each note recorded exactly one of W/U/S.
tally_chars="$(cat "$TALLY" 2>/dev/null || true)"
WRITTEN="$(printf '%s' "$tally_chars" | tr -cd 'W' | wc -c | tr -d ' ')";   WRITTEN="${WRITTEN:-0}"
UNCHANGED="$(printf '%s' "$tally_chars" | tr -cd 'U' | wc -c | tr -d ' ')"; UNCHANGED="${UNCHANGED:-0}"
SKIPPED="$(printf '%s' "$tally_chars" | tr -cd 'S' | wc -c | tr -d ' ')";   SKIPPED="${SKIPPED:-0}"
echo "build-vault: vault at $DEST"
if [ "${SKIPPED:-0}" -gt 0 ]; then
  echo "build-vault: $WRITTEN note(s) written, $UNCHANGED unchanged, $SKIPPED skipped (runs: $run_count, contracts: ${#contract_files[@]}, memory: $HAVE_MEMORY, lessons: $HAVE_LESSONS)"
else
  echo "build-vault: $WRITTEN note(s) written, $UNCHANGED unchanged (runs: $run_count, contracts: ${#contract_files[@]}, memory: $HAVE_MEMORY, lessons: $HAVE_LESSONS)"
fi
exit 0
