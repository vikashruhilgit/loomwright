#!/usr/bin/env bash
# build-capabilities.sh — generate loomwright/capabilities.json, the published, versioned
# capability contract a host reads instead of parsing Loomwright's internal files.
#
# WHY: a host (Loomwright Studio is the first) needs to know which agents (with the exact runtime
# agent_type), commands, skills, result schemas and hooks the installed plugin offers, and what each
# hook writes into the session's working directory. Those facts live in plugin.json, frontmatter,
# hooks.json and the result-schema docs — shapes that are Loomwright's to change between releases.
# This script derives ONE stable document from them. Schema + compatibility policy:
# docs/CAPABILITIES_CONTRACT.md. It is a different file from docs/CAPABILITY_BASELINE.json, which is
# INBOUND (the harness features Loomwright uses); this one is OUTWARD (what Loomwright offers).
#
# usage: build-capabilities.sh [--root <plugin-root>] [--out <file>] [--check]
#   (default)   write <plugin-root>/capabilities.json
#   --out FILE  write FILE instead (the self-test uses it to build a mutant without touching a tree)
#   --check     regenerate to a temp file and compare byte-for-byte with <plugin-root>/capabilities.json;
#               exit 1 with ONE line when they differ (the CI / ci-local staleness gate)
#   --root DIR  the plugin root to read (default: this script's parent dir) — lets the test run on a
#               fixture copy of the plugin tree
# exit: 0 ok · 1 stale (--check) or a fail-CLOSED source inconsistency · 2 usage
#
# DETERMINISM: every list is sorted (jq sort / sort_by, codepoint order, locale-independent), keys are
# sorted (jq -S), there are no timestamps, and no path in the output is absolute or depends on --root.
# hooks[].scripts[] is the one list kept in INVOCATION order, because order is its meaning.
#
# Bash 3.2 / BSD-safe: no GNU-only flags, no `stat`/`date`, `env LC_ALL=C sort` for file order.
set -uo pipefail

ROOT=""; OUT=""; CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "build-capabilities: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || { echo "build-capabilities: --out needs a file" >&2; exit 2; }; OUT="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "build-capabilities: unknown argument '$1' (usage: [--root DIR] [--out FILE] [--check])" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -d "$ROOT" ] || { echo "build-capabilities: plugin root '$ROOT' is not a directory" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "build-capabilities: jq is required" >&2; exit 1; }

CONTRACT_SCHEMA_VERSION=1
MANIFEST="$ROOT/.claude-plugin/plugin.json"
HOOKS="$ROOT/hooks/hooks.json"
SCHEMA_INDEX="$ROOT/docs/RESULT_SCHEMAS.md"
for f in "$MANIFEST" "$HOOKS" "$SCHEMA_INDEX"; do
  [ -f "$f" ] || { echo "build-capabilities: required source missing: ${f#"$ROOT"/}" >&2; exit 1; }
done

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/build-capabilities.XXXXXX")" || { echo "build-capabilities: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$tmpd"' EXIT
US="$(printf '\037')"   # field separator for the per-file records (no source field carries it)

# ---------------------------------------------------------------------------------------------------
# writes[] AUDIT — script basename -> what it may create, modify or delete in the session's working
# directory (the user project; for scripts that resolve the MAIN checkout via `git worktree list`,
# that checkout). Out of scope: anything under ~/ or $TMPDIR, the harness's own env file, network
# egress, and desktop notifications. Directories (mkdir / mkdir-as-lock) are not writes; a same-dir
# temp file that is renamed onto a listed path or removed before exit is not listed separately.
# A path is repo-relative with <placeholders>; a settings key is `<file>#<json.path>`.
#   w <script> <path>     — the script (or a script it runs) may write <path>
#   w <script> -          — audited: writes nothing in scope
#   w <script> unknown    — audited, but the writes cannot be determined statically
# A hook script with NO entry here is emitted as writes: ["unknown"] — never a silent [].
# This table is a HAND audit: the staleness gate re-runs this generator, it does not re-read the
# scripts. Each entry names the construct it was read from so a reviewer can re-check it.
# ---------------------------------------------------------------------------------------------------
AUDIT=""
w() { AUDIT="$AUDIT$1$US$2
"; }

# validate-*-result.py — read the payload/transcript, print a decision on stdout; no open(..., 'w'),
# no os.replace / rename, no subprocess (result_block_parser.py opens files read-only).
w validate-code-review-result.py -
w validate-execute-result.py -
w validate-launch-pad-result.py -
w validate-plan-review-result.py -
w validate-qa-result.py -
w validate-supervisor-result.py -
w validate-worker-result.py -
# set-otel-resource-attrs.sh — `jq '.env = (... {OTEL_RESOURCE_ATTRIBUTES:$a})' "$SL" > "$tmp"; mv "$tmp" "$SL"`
# (or `jq -n ... > "$SL"` when absent), SL="$ROOT/.claude/settings.local.json". Its CLAUDE_ENV_FILE
# append is the harness's env file, outside the working directory.
w set-otel-resource-attrs.sh '.claude/settings.local.json#env.OTEL_RESOURCE_ATTRIBUTES'
# emit-lifecycle.sh — `printf '%s\n' "$LINE" >> "$LOG_FILE"`, LOG_FILE="$LOG_DIR/${SESSION_ID}.jsonl",
# LOG_DIR="$main_root/.supervisor/logs"; heartbeat debounce `printf ... > "$DEBOUNCE_FILE"`
# ($LOG_DIR/.lifecycle-heartbeat-debounce-<agent>); ask ledger `>> "$ASK_IDS_FILE"` + tail/mv.
w emit-lifecycle.sh '.supervisor/logs/<session>.jsonl'
w emit-lifecycle.sh '.supervisor/logs/.lifecycle-heartbeat-debounce-<agent>'
w emit-lifecycle.sh '.supervisor/logs/.lifecycle-asked-ids'
# emit-token-ledger.sh — `printf '%s\n' "$LINE" >> "$LOG_FILE"` ($LOG_DIR/${SESSION_ID}.jsonl under
# the main checkout); one-time `: > "$_flag"` when python3 is missing. `mkdir "$_lock"` is a dir lock.
w emit-token-ledger.sh '.supervisor/logs/<session>.jsonl'
w emit-token-ledger.sh '.supervisor/logs/token-ledger-python3-missing.flag'
# stamp-requirement-status.sh — `{ printf '\n## Status: brief-shipped\n' ...; } >> "$req"`, req = the
# brief's contained `Source requirement` pointer under .supervisor/requirements/. LOCK is a dir.
w stamp-requirement-status.sh '.supervisor/requirements/<requirement>.md'
# send-telemetry.sh — `>> "$LOG_FILE"` ($PWD/.supervisor/logs/telemetry.log); `: > "$FLAG"` and
# `: > "$REPO_UNSET_FLAG"` (telemetry-*-shown-<session or nosession-hour>.flag); it pipes into
# send-telemetry-core.sh, which appends `>> "$SENT_LOG"` (.supervisor/logs/telemetry-sent.log).
w send-telemetry.sh '.supervisor/logs/telemetry.log'
w send-telemetry.sh '.supervisor/logs/telemetry-pending-shown-<key>.flag'
w send-telemetry.sh '.supervisor/logs/telemetry-repo-unset-shown-<key>.flag'
w send-telemetry.sh '.supervisor/logs/telemetry-sent.log'
# emit-progress-event.sh — `printf '%s\n' "$LINE" >> "$LOG_FILE"` ($main_root/.supervisor/logs/<session>.jsonl),
# then `bash "$SCRIPT_DIR/build-state.sh"`, which `mv -f "$TMP" "$STATE_MD"` (.supervisor/state.md).
w emit-progress-event.sh '.supervisor/logs/<session>.jsonl'
w emit-progress-event.sh '.supervisor/state.md'
# reproject-state-on-terminal.sh — only `bash "$SCRIPT_DIR/build-state.sh"` (-> .supervisor/state.md).
w reproject-state-on-terminal.sh '.supervisor/state.md'
# send-webhook.sh — curl POSTs only; its resolver resolve-egress-config.sh reads config, writes nothing.
w send-webhook.sh -
# hook-dispatch-on-pr-create.sh — `bash "$DISPATCHER"` (dispatch-pr-review.sh), which starts a
# DETACHED `claude -p --agent review-pr-runner` heal loop; what that agent edits and commits is
# decided at run time, so the writes cannot be listed statically.
w hook-dispatch-on-pr-create.sh unknown
# worktree-audit.sh (record) — `printf '%s\n' "$line" >> "$dir/worktrees.log"`, dir="$root/.supervisor/logs".
w worktree-audit.sh '.supervisor/logs/worktrees.log'
# seed-run-owner.sh — `printf ... > "$OWNER_FILE"`, OWNER_FILE="$LOG_DIR/${PLUGIN_SESSION_ID}.owner".
w seed-run-owner.sh '.supervisor/logs/<session>.owner'
# emit-agent-identity.sh — `printf '%s\n' "$LINE" >> "$LOG_FILE"` ($LOG_DIR/${CC_SESSION_ID}.jsonl).
w emit-agent-identity.sh '.supervisor/logs/<session>.jsonl'
# notify-desktop.sh — `>> "$NOTIFY_LOG"` (.supervisor/logs/notifications.log), `>> "$NOTIFIED_IDS_FILE"`
# + tail/mv (.supervisor/logs/.notified-ids), `> "$DEBOUNCE_FILE"` (.supervisor/logs/.notify-debounce).
w notify-desktop.sh '.supervisor/logs/notifications.log'
w notify-desktop.sh '.supervisor/logs/.notified-ids'
w notify-desktop.sh '.supervisor/logs/.notify-debounce'
# guard-test-integrity.sh — a PreToolUse gate: reads the .supervisor/guard/ markers and prints a
# decision; its `>`/`>>` tokens are the command TOKENISER's literals, not redirections.
w guard-test-integrity.sh -
# guard-arm.sh — arm: `printf ... > "$tmp"; mv -f "$tmp" "$marker"`, marker="$GUARD_DIR/$sid.json";
# disarm-session / stale sweep: `rm -f "$GUARD_DIR/$sid.json"`. GUARD_DIR=<project>/.supervisor/guard.
w guard-arm.sh '.supervisor/guard/<session>.json'
# close-stranded-run.sh — `>> "$LOG_FILE"` ($LOG_DIR/<session>.jsonl), `bash build-state.sh`
# (.supervisor/state.md), `bash run-lock.sh release`, which `rm -rf "$LOCK_DIR"` (.supervisor/run.lock/meta).
w close-stranded-run.sh '.supervisor/logs/<session>.jsonl'
w close-stranded-run.sh '.supervisor/state.md'
w close-stranded-run.sh '.supervisor/run.lock/meta'
# session-resume.sh — nudge markers `: > "$marker"` (.supervisor/.curation-nudge-shown,
# .supervisor/.stranded-nudge-shown, .supervisor/.rules-nudge-shown); `reconcile-jobs.sh
# --repair-merged` moves a stranded_merged brief (`mv "$tmp" "$dest"`, dest=.supervisor/jobs/done/,
# then `rm -f "$brief"` from .supervisor/jobs/in-progress/); read-rules.sh appends `>> "$LOG"`
# (.supervisor/logs/memory.log); read-system-contract.sh appends `>> "$LOG"` (.supervisor/logs/twin.log);
# the observability warning pipes into notify-desktop.sh (its three files). Its own
# ~/.claude/loomwright/observability marker is under ~/, out of scope.
w session-resume.sh '.supervisor/.curation-nudge-shown'
w session-resume.sh '.supervisor/.stranded-nudge-shown'
w session-resume.sh '.supervisor/.rules-nudge-shown'
w session-resume.sh '.supervisor/jobs/done/<brief>.md'
w session-resume.sh '.supervisor/jobs/in-progress/<brief>.md'
w session-resume.sh '.supervisor/logs/memory.log'
w session-resume.sh '.supervisor/logs/twin.log'
w session-resume.sh '.supervisor/logs/notifications.log'
w session-resume.sh '.supervisor/logs/.notified-ids'
w session-resume.sh '.supervisor/logs/.notify-debounce'

printf '%s' "$AUDIT" > "$tmpd/audit.tsv"
jq -R -s --arg us "$US" '
  split("\n") | map(select(length > 0) | split($us)) | group_by(.[0])
  | map({key: .[0][0], value: (map(.[1]) | map(select(. != "-")) | unique
                               | if index("unknown") then ["unknown"] else . end)})
  | from_entries' "$tmpd/audit.tsv" > "$tmpd/audit.json" || { echo "build-capabilities: audit table did not parse" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------------
# frontmatter FILE — the block between a line-1 `---` and the next `---` (nothing when line 1 is not `---`).
frontmatter() { awk 'NR == 1 { if ($0 != "---") exit; f = 1; next } f && $0 == "---" { exit } f { print }' "$1"; }
# fmval FILE KEY — a top-level frontmatter scalar: surrounding quotes stripped; for a `|`/`>` block
# scalar, the first line of the block.
fmval() {
  frontmatter "$1" | awk -v k="$2" -v q="'" '
    blk { if ($0 ~ /^[ \t]+[^ \t]/) { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print; exit } if ($0 !~ /^[ \t]*$/) exit; next }
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "|" || v == ">" || v == "|-" || v == ">-") { blk = 1; next }
      if (length(v) >= 2 && ((substr(v, 1, 1) == "\"" && substr(v, length(v), 1) == "\"") || (substr(v, 1, 1) == q && substr(v, length(v), 1) == q)))
        v = substr(v, 2, length(v) - 2)
      print v; exit
    }'
}
sorted_glob() { # sorted_glob DIR PATTERN — one path per line, locale-independent order
  ( cd "$1" 2>/dev/null && for p in $2; do [ -e "$p" ] && printf '%s\n' "$p"; done ) | env LC_ALL=C sort
}

# ---------------------------------------------------------------------------------------------------
# result_schemas[] — the RESULT_SCHEMAS.md index headings whose first non-blank body line is
# `See [result-schemas/<x>.md](result-schemas/<x>.md).`; name = leading identifier token of the
# heading after stripping backticks and a trailing parenthetical; schema_version = the HIGHEST
# `schema_version: N` in the linked file (null when it records none).
# Explicit exclusions — index sections that link a split file but are not schemas:
EXCLUDED_SCHEMA_HEADINGS="Schema Versioning|Validation Location"
# ---------------------------------------------------------------------------------------------------
awk -v us="$US" '
  /^## / { h = substr($0, 4); pending = 1; next }
  pending && /^[ \t]*$/ { next }
  pending {
    pending = 0
    if (match($0, /^See \[result-schemas\/[^]]+\.md\]\(result-schemas\/[^)]+\.md\)\.$/)) {
      s = $0; sub(/^See \[result-schemas\//, "", s); a = s; sub(/\].*$/, "", a)
      b = s; sub(/^[^(]*\(result-schemas\//, "", b); sub(/\)\.$/, "", b)
      if (a == b) print h us a
    }
  }' "$SCHEMA_INDEX" > "$tmpd/schema-headings.tsv"
: > "$tmpd/schemas.tsv"
while IFS="$US" read -r heading file; do
  [ -n "$heading" ] || continue
  case "|$EXCLUDED_SCHEMA_HEADINGS|" in *"|$heading|"*) continue ;; esac
  name="$(printf '%s' "$heading" | tr -d '`' | sed -E 's/[[:space:]]*\([^()]*\)[[:space:]]*$//' | grep -oE '^[A-Za-z_][A-Za-z0-9_]*' | head -n1)"
  [ -n "$name" ] || { echo "build-capabilities: RESULT_SCHEMAS.md heading '$heading' has no identifier" >&2; exit 1; }
  linked="$ROOT/docs/result-schemas/$file"
  [ -f "$linked" ] || { echo "build-capabilities: RESULT_SCHEMAS.md §$name links result-schemas/$file, which does not exist" >&2; exit 1; }
  ver="$(grep -oE 'schema_version"?:[[:space:]]*`?[0-9]+' "$linked" | grep -oE '[0-9]+$' | env LC_ALL=C sort -n | tail -n1)"
  # Fail-CLOSED: a looser read (`schema_version` then up to 8 non-alphanumerics then digits) must find
  # the same highest version. A version recorded in a form the strict pattern misses (e.g.
  # `schema_version = 3`, `"schema_version": "3"`) would otherwise publish null ("none recorded").
  loose="$(grep -oE 'schema_version[^A-Za-z0-9]{0,8}[0-9]+' "$linked" | grep -oE '[0-9]+$' | env LC_ALL=C sort -n | tail -n1)"
  [ "$loose" = "$ver" ] || { echo "build-capabilities: result-schemas/$file records schema_version in a form the generator does not parse (strict '${ver:-none}', loose '${loose:-none}') — write it as \`schema_version: N\`" >&2; exit 1; }
  printf '%s%s%s\n' "$name" "$US" "${ver:-null}" >> "$tmpd/schemas.tsv"
done < "$tmpd/schema-headings.tsv"
[ -s "$tmpd/schemas.tsv" ] || { echo "build-capabilities: no result schemas parsed from RESULT_SCHEMAS.md" >&2; exit 1; }
dups="$(cut -d "$US" -f1 "$tmpd/schemas.tsv" | env LC_ALL=C sort | uniq -d)"
[ -z "$dups" ] || { echo "build-capabilities: duplicate result-schema name(s): $dups" >&2; exit 1; }

# Fail-CLOSED cross-check: every schema the index's opening paragraph names explicitly as
# `NAME at \`schema_version: N\`` must match the linked file's current version. The paragraph's
# "all others at schema_version: 1" catch-all is NOT checked (it names no schema).
awk '/^## /{exit} {print}' "$SCHEMA_INDEX" | grep -oE '[A-Z][A-Z0-9_]+ at `schema_version: [0-9]+`' \
  | sed -E 's/ at `schema_version: ([0-9]+)`/ \1/' > "$tmpd/index-claims.txt" || true
while read -r cname cver; do
  [ -n "$cname" ] || continue
  got="$(awk -F "$US" -v n="$cname" '$1 == n { print $2 }' "$tmpd/schemas.tsv")"
  if [ "$got" != "$cver" ]; then
    echo "build-capabilities: RESULT_SCHEMAS.md says $cname is at schema_version $cver but result-schemas/ records '${got:-<no such schema>}' — fix the doc or the schema file" >&2
    exit 1
  fi
done < "$tmpd/index-claims.txt"

jq -R -s --arg us "$US" 'split("\n") | map(select(length > 0) | split($us)
  | {name: .[0], schema_version: (if .[1] == "null" then null else (.[1] | tonumber) end)}) | sort_by(.name)' \
  "$tmpd/schemas.tsv" > "$tmpd/schemas.json" || exit 1
SCHEMA_NAMES="$(cut -d "$US" -f1 "$tmpd/schemas.tsv" | tr '\n' ' ')"

# ---------------------------------------------------------------------------------------------------
# agents[] — frontmatter name/model/tools/disallowedTools; runtime_agent_type = <plugin name>:<name>
# (the frontmatter name already carries the plugin prefix, so the runtime reports it doubled).
# result_blocks[] = every result-schema name the body EMITS: a line that is exactly the block name,
# optionally as a `#` heading and/or with a trailing `:` (an emission template), never a prose mention.
# result_block = the only block, or — for several — the one the documented precedence below picks
# (keyed by the block SET, never by agent name); several with no rule => null.
# ---------------------------------------------------------------------------------------------------
PRIMARY_RULES='{
  "EXECUTE_CHECKPOINT,EXECUTE_RESULT": "EXECUTE_RESULT",
  "QA_RESULT,VERIFY_RESULT": "QA_RESULT"
}'
# EXECUTE_RESULT: the Execute Manager's FINAL block; EXECUTE_CHECKPOINT is the mid-run resume handoff
#   (both validated by validate-execute-result.py — docs/result-schemas/execute-checkpoint.md).
# QA_RESULT: validate-qa-result.py's documented rule — "QA_RESULT wins whenever present"; VERIFY_RESULT
#   is the --verify mode's block (docs/RESULT_SCHEMAS.md opening paragraph, §VERIFY_RESULT).
PLUGIN_NAME="$(jq -r '.name // empty' "$MANIFEST")"
PLUGIN_VERSION="$(jq -r '.version // empty' "$MANIFEST")"
[ -n "$PLUGIN_NAME" ] && [ -n "$PLUGIN_VERSION" ] || { echo "build-capabilities: plugin.json lacks .name or .version" >&2; exit 1; }

: > "$tmpd/agents.tsv"
while IFS= read -r rel; do
  f="$ROOT/agents/$rel"
  name="$(fmval "$f" name)"
  [ -n "$name" ] || { echo "build-capabilities: agents/$rel has no frontmatter name" >&2; exit 1; }
  # Emission-template lines naming a *_RESULT block the index does not know are printed with a `?`
  # prefix and fail the run closed — a silent drop would publish "emits no block".
  blocks="$(awk -v names=" $SCHEMA_NAMES " '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm { if ($0 == "---") fm = 0; next }
    { l = $0; sub(/^[ \t]+/, "", l); sub(/^#+[ \t]*/, "", l); sub(/[ \t]+$/, "", l); sub(/:$/, "", l)
      if (l ~ /^[A-Z][A-Z0-9_]*$/) { if (index(names, " " l " ")) print l; else if (l ~ /_RESULT$/) print "?" l } }' "$f" | env LC_ALL=C sort -u | paste -s -d, -)"
  case ",$blocks" in *",?"*)
    echo "build-capabilities: agents/$rel emits result block(s) RESULT_SCHEMAS.md does not index: $(printf '%s' "$blocks" | tr ',' '\n' | grep '^?' | tr -d '?' | paste -s -d, -)" >&2; exit 1 ;;
  esac
  # tools: a key that is ABSENT means the agent inherits every tool (published as null, never []);
  # a key that is PRESENT but has no inline comma list (e.g. a YAML block list) is not parsed => fail closed.
  for k in tools disallowedTools; do
    if frontmatter "$f" | grep -qE "^$k:"; then
      [ -n "$(fmval "$f" "$k")" ] || { echo "build-capabilities: agents/$rel has a '$k:' key the generator cannot parse (write it as an inline comma-separated list)" >&2; exit 1; }
    fi
  done
  tools_v="$(fmval "$f" tools)"
  frontmatter "$f" | grep -qE '^tools:' || tools_v="$(printf '\002')"   # sentinel: key absent
  printf '%s%s%s%s%s%s%s%s%s%s%s\n' "$name" "$US" "$(fmval "$f" model)" "$US" "$tools_v" "$US" \
    "$(fmval "$f" disallowedTools)" "$US" "$blocks" "$US" "$rel" >> "$tmpd/agents.tsv"
done < <(sorted_glob "$ROOT/agents" '*.md')

jq -R -s --arg us "$US" --arg plugin "$PLUGIN_NAME" --argjson rules "$PRIMARY_RULES" '
  def csv: split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0));
  split("\n") | map(select(length > 0) | split($us)
    | (if .[2] == "\u0002" then null else (.[2] | csv) end) as $tools | (.[3] | csv) as $deny | (.[4] | csv) as $blocks
    | {name: .[0],
       runtime_agent_type: ($plugin + ":" + .[0]),
       model: (if .[1] == "" then null else .[1] end),
       tools: (if $tools == null then null else ($tools - $deny | unique) end),
       result_blocks: $blocks,
       result_block: (if ($blocks | length) == 0 then null
                      elif ($blocks | length) == 1 then $blocks[0]
                      else ($rules[$blocks | join(",")] // null) end)})
  | sort_by(.name)' "$tmpd/agents.tsv" > "$tmpd/agents.json" || exit 1

# commands[] — file stem + first line of the frontmatter description.
: > "$tmpd/commands.tsv"
while IFS= read -r rel; do
  printf '%s%s%s\n' "${rel%.md}" "$US" "$(fmval "$ROOT/commands/$rel" description)" >> "$tmpd/commands.tsv"
done < <(sorted_glob "$ROOT/commands" '*.md')
jq -R -s --arg us "$US" 'split("\n") | map(select(length > 0) | split($us)
  | {name: .[0], description: (if (.[1] // "") == "" then null else .[1] end)}) | sort_by(.name)' \
  "$tmpd/commands.tsv" > "$tmpd/commands.json" || exit 1

# skills[] — frontmatter name, else the directory name.
: > "$tmpd/skills.tsv"
while IFS= read -r rel; do
  d="${rel%/SKILL.md}"
  n="$(fmval "$ROOT/skills/$rel" name)"
  printf '%s%s%s\n' "${n:-$d}" "$US" "$d" >> "$tmpd/skills.tsv"
done < <(sorted_glob "$ROOT/skills" '*/SKILL.md')
jq -R -s --arg us "$US" 'split("\n") | map(select(length > 0) | split($us) | {name: .[0]}) | sort_by(.name)' \
  "$tmpd/skills.tsv" > "$tmpd/skills.json" || exit 1

# ---------------------------------------------------------------------------------------------------
# hooks[] — one entry per hooks.json leaf (.hooks.<Event>[g].hooks[l]).
#   script    first plugin script the command references (scripts/<x>), null when none
#   scripts   every plugin script referenced, in invocation order — matched, with ROOT_VAR the
#             install-root variable below, as `$ROOT_VAR/scripts/<x>`, `${ROOT_VAR}/scripts/<x>` or
#             `"${ROOT_VAR}"/scripts/<x>`
#   blocking  false only for a `type: command` leaf whose command ENDS in `|| true` (a `|| true`
#             earlier in the command does not make the last command's exit status fail-safe)
#   writes    sorted union of the leaf's inline redirect targets and each script's audited writes;
#             ["unknown"] when ANY part is unaudited or unparseable (unknown wins). /dev/null and fd
#             duplications (2>&1) are not writes; `mkdir -p <dir>` is a directory, not a write.
#             FAIL-CLOSED PARSER: the leaf is ["unknown"] whenever the parser meets something it does
#             not model — an install-root-variable mention that is not a parsed script path; a redirect
#             whose target is empty or not a literal path (`&>`, `>|` and `N>` are parsed as writes);
#             a `<>` read-write open; or a simple command whose first word is not on the
#             non-writing allowlist below (so tee, cp, mv, rm, touch, sed -i, eval, `bash -c`, … are
#             unknown), or an interpreter not followed by a plugin script path.
NONWRITING_CMDS='cat printf echo mkdir date true false : test ['
INTERPRETERS='bash sh python3 python'
ROOT_VAR='CLAUDE_PLUGIN_ROOT'   # the one place the generator names the install-root variable

# Sorted by (event, matcher with null as "", group position, leaf position); `source` records the
# position so an entry can be traced back to hooks.json.
# ---------------------------------------------------------------------------------------------------
jq -S --slurpfile audit "$tmpd/audit.json" \
  --arg nonwriting "$NONWRITING_CMDS" --arg interp "$INTERPRETERS" --arg rv "$ROOT_VAR" '
  ($audit[0]) as $a
  | ("\\$\\{?" + $rv + "\\}?\"?/scripts/([A-Za-z0-9_.-]+)") as $script_re
  | ($nonwriting | split(" ")) as $okcmds | ($interp | split(" ")) as $interps
  # simple_cmds: the command text split into simple commands. `$(` opens one, and the operators
  # ; & && || | ( and newline separate them; fd duplications are blanked and &> / >| normalised to >
  # first so their `&` / `|` does not split. Leading VAR=value assignments and `!` are dropped. Over-splitting inside a
  # quoted string can only yield an unrecognised first word, i.e. unknown — never a false [].
  | def simple_cmds: gsub("[0-9]*>&[0-9-]*"; " ") | gsub("&>"; ">") | gsub(">\\|"; ">") | gsub("\\$\\("; ";")
      | [splits("&&|\\|\\||[;&|(\n]")]
      | map(sub("^[ \t]+"; "") | sub("^!+[ \t]*"; "")
            | until(test("^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*([ \t]+|$)") | not;
                    sub("^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]*"; "")))
      | map(select(length > 0));
    # a simple command is understood iff its first word is a non-writing builtin/utility, or an
    # interpreter whose next word is a plugin script path (whose writes come from the audit).
    def understood: ([splits("[ \t]+")] | map(select(length > 0))) as $w
      | ($w[0] | sub("\\)+$"; "")) as $c
      | if ($okcmds | index([$c])) then true
        elif ($interps | index([$c])) then (($w[1] // "") | test($script_re))
        else false end;
  [ .hooks | to_entries[] | .key as $ev | .value | to_entries[] | .key as $g | .value as $grp
      | $grp.hooks | to_entries[] | .key as $l | .value as $h
      | ($h.command // "") as $cmd
      | [ $cmd | scan($script_re) | .[0] ] as $s
      | ([ $cmd | scan($rv) ] | length) as $mentions
      | [ $cmd | scan("(?<![<>&0-9])(?:[0-9]*|&)(?:>\\||>>?)[ \\t]*(&[0-9-]*|[^ \\t;|&)<>]*)") | .[0]
          | select(. != "/dev/null" and . != "\"/dev/null\"" and (startswith("&") | not)) ] as $inline
      | ($inline | map(if (length == 0) or test("[$\"\u0027`(){}*?~\\\\]") then "unknown" else . end)) as $iw
      | ($s | map($a[.] // ["unknown"]) | add // []) as $sw
      | (if ($h.type == "command")
           and (($mentions != ($s | length))
                or ($cmd | test("<>"))
                or ([$cmd | simple_cmds[] | understood] | all | not))
         then ["unknown"] else [] end) as $uw
      | (($iw + $sw + $uw) | unique) as $all
      | {event: $ev,
         matcher: ($grp.matcher // null),
         type: $h.type,
         source: ("hooks." + $ev + "[" + ($g | tostring) + "].hooks[" + ($l | tostring) + "]"),
         _g: $g, _l: $l,
         script: (if ($s | length) > 0 then ("scripts/" + $s[0]) else null end),
         scripts: ($s | map("scripts/" + .)),
         blocking: ($h.type == "command" and ($cmd | test("\\|\\|[ \\t]*true[ \\t]*$") | not)),
         writes: (if ($all | index("unknown")) then ["unknown"] else $all end)} ]
  | sort_by(.event, (.matcher // ""), ._g, ._l) | map(del(._g, ._l))' "$HOOKS" > "$tmpd/hooks.json" \
  || { echo "build-capabilities: hooks.json did not parse" >&2; exit 1; }

jq -n -S \
  --argjson v "$CONTRACT_SCHEMA_VERSION" --arg pn "$PLUGIN_NAME" --arg pv "$PLUGIN_VERSION" \
  --slurpfile agents "$tmpd/agents.json" --slurpfile commands "$tmpd/commands.json" \
  --slurpfile skills "$tmpd/skills.json" --slurpfile schemas "$tmpd/schemas.json" \
  --slurpfile hooks "$tmpd/hooks.json" '
  {contract_schema_version: $v,
   generated_by: "loomwright/scripts/build-capabilities.sh",
   plugin_name: $pn,
   plugin_version: $pv,
   agents: $agents[0], commands: $commands[0], skills: $skills[0],
   result_schemas: $schemas[0], hooks: $hooks[0],
   host_switch: null}' > "$tmpd/capabilities.json" || { echo "build-capabilities: assembly failed" >&2; exit 1; }

if [ "$CHECK" -eq 1 ]; then
  if [ -f "$ROOT/capabilities.json" ] && cmp -s "$tmpd/capabilities.json" "$ROOT/capabilities.json"; then
    exit 0
  fi
  echo "capabilities.json is stale — run: bash loomwright/scripts/build-capabilities.sh and commit" >&2
  exit 1
fi
dest="${OUT:-$ROOT/capabilities.json}"
cp "$tmpd/capabilities.json" "$dest" || { echo "build-capabilities: could not write $dest" >&2; exit 1; }
exit 0
