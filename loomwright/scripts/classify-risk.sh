#!/usr/bin/env bash
# classify-risk.sh — the ONE deterministic implementation of the high-risk-diff heuristic that
# `skills/self-heal-advisory/SKILL.md` §"Advisory red-team lens" used to carry as prompt pseudo-code
# and that `automate-helpers.sh gate-eval` now judges as its sixth fail-CLOSED condition. Read-only:
# it never writes, never `cd`s into --root (every git call is `git -C "$root"`), never executes any
# content it reads (no eval / source — project patterns are matched with `case` and `grep -F` only).
#
# Usage:
#   classify-risk.sh <base_ref> <head_ref> [--root <dir>]   # default --root .
#   classify-risk.sh --kind-table                           # print the heuristic as a markdown table
#
# Output (ONE JSON object on stdout, always exit 0):
#   {"high_risk": true|false|null,
#    "reasons": ["path: <file> matched <pattern>", "content: N changed line(s) matched <pattern>",
#                "size: changed_lines N > 400", "trusted-root: <file>",
#                "project: <file> matched <glob>", ...],
#    "changed_files": N, "changed_lines": N, "source": "classify-risk.sh"}
#   Reasons are prefixed `path:` / `content:` / `size:` / `trusted-root:` / `project:`, name the
#   matched pattern (a `trusted-root:` reason names the lowercased changed path itself), are
#   deduplicated, and are capped at 20 followed by one `+N more` entry.
#
# The heuristic (verbatim from the lens; `--kind-table` prints it from the SAME data lists below):
#   (a) security / financial / migration surfaces — path OR content, case-insensitive:
#       *auth*, *authz*, *security*, *crypto*, *secret*, *token*, *payment*, migrations/, *migration*
#   (b) workflow-automation / orchestration / cross-agent prompt surfaces —
#       any changed path under .github/workflows/, hooks/, agents/, commands/, command-parts/, skills/
#       (the directory at the path root or anywhere below it — `command-parts/` is where the split
#       command docs' moved text lives, `docs/command-parts/<cmd>/`, so a parts-only edit to /setup,
#       /dreaming or /agent-help is as high-risk as the same edit to its router), OR path/content
#       matching (case-insensitive):
#       workflow, automation, orchestration
#   (c) sheer size — changed_lines > 400 OR changed_files > 15, where changed_lines is the count of
#       `+`/`-` lines of `git diff <base>...<head>` (the `+++`/`---` file headers excluded) and
#       changed_files is the line count of `git diff <base>...<head> --name-only`. Three-dot, as the
#       lens always diffed.
#   "content" means the ADDED and REMOVED lines of that diff (not context lines and not the diff
#   headers — otherwise every path match would double as a content match).
#   trusted-root — the instruction / config files a PR is judged by. The names live ONLY in the two
#       data lists below: TRUSTED_ROOT_ANYDEPTH (exact basename at any depth) and
#       TRUSTED_ROOT_ROOTONLY (repo root only: exact path — a `/`-terminated directory also as its
#       bare `/`-less path — under a `/`-terminated directory, or an ANCESTOR of an entry, so a
#       symlink replacing the root config directory, or `.agent -> agentcfg`, cannot install
#       new config unseen).
#       Matched case-insensitively against BOTH sides of a rename (`git diff --name-only
#       --no-renames -z <base>...<head>`), never as a substring. One `trusted-root: <lowercased
#       path>` reason per matching path.
#
# Project extension — `.agent/risk.json` at `<base_ref>` (committed, ADD-ONLY; owner decision R5):
#   {"schema_version": 1, "paths": ["billing/**"], "content": ["stripe"]}
#   `paths[]` are shell `case` patterns matched against each changed path lowercased (so `*` and
#   `**` BOTH match across `/`, `?` matches one character, `[..]` is a class); `content[]` are
#   LITERAL words matched case-insensitively (`grep -iF`) against the changed lines. Both only ADD
#   surfaces: there is NO `exclude` key, NO flag, NO config key and NO way to mark a diff low-risk —
#   an `exclude` key present is ignored with `risk_json_exclude_ignored` on stderr, never honoured.
#   Malformed file (invalid JSON, non-object root, `paths`/`content` not an array of strings,
#   `schema_version` present but not 1) ⇒ generic-only result + `risk_json_malformed` on stderr —
#   never a failure and never `null`. Absent at `<base_ref>` (`git ls-tree --full-tree <base>
#   -- .agent/risk.json` succeeds and lists nothing) ⇒ silent generic-only; a FAILED probe
#   (non-zero exit) ⇒ `unclassifiable: git_failed` (null), never read as absence. The file is
#   read ONLY from `<base_ref>` (`git -C <root> show`), never from the working tree
#   or `<head_ref>`, so a PR cannot drop an entry and change the guarded path in one diff; `--root`
#   picks the repository only. A present blob that `git show` cannot read ⇒
#   `unclassifiable: git_failed` (null), never a silent drop of the project's entries.
#
# Failure-mode split (CLAUDE.md §"Failure-Mode Invariants"): this script is a fail-SAFE EMITTER —
# it always exits 0. `high_risk: null` + `reasons: ["unclassifiable: <reason>"]` + the reason on
# stderr is emitted when the diff cannot be classified (bad_args, jq_missing, not_a_git_repo,
# bad_ref, git_failed). Its CONSUMERS fail CLOSED: `gate-eval` parks on anything but an explicit
# `false` (`PARK: high_risk_diff`) with no override of any kind, and the Phase 4.5 lens treats
# `null` as "spawn the advisory pass" (the safe direction for an advisory lens is to run it).
# The jq-less `jq_missing` object (and a `bad_args` seen before jq is known) is the ONE
# shell-templated object in this file — fixed literals only, no caller text; every other object is
# built with `jq --arg` / `--argjson`.
#
# HONEST LIMITS: the match is pattern-based, not semantic — a comment or a variable containing
# `token` trips (a); a path under `skills/` trips (b) however small the change. An ADDED line whose
# own content begins with `++` (or a REMOVED one beginning `--`) diffs as `+++…`/`---…`, is
# indistinguishable from a file header, and is not counted (nor content-matched). In an
# agent-orchestration repo (this one) nearly every PR touches agents/, commands/ or skills/, so
# nearly every PR is high-risk by construction — that is the owner's intent (R5), not a bug. The
# same holds for trusted-root: any PR touching a CLAUDE.md (at any depth) parks the merge gate.
# Trusted-root matching is by name only — an instruction file under any other name (an `@`-import
# target, a skill file outside the listed paths) is caught only if a generic branch catches it.
#
# Co-located static suite: test-classify-risk.sh.
#
# `set -f` (noglob) is LOAD-BEARING: the heuristic lists below are glob-SHAPED words (`*auth*`,
# `*token*`, `migrations/`, ...) iterated by unquoted word-split, and without `-f` every one of them
# pathname-expands against the CALLER'S cwd — an untracked `oauth2-proxy.yml` or a top-level
# `payments/` in the project silently replaced the pattern with the filename and turned an honest
# `true` into `false` (fail-OPEN — the gate cannot see it). No intentional pathname expansion exists
# in this file; `case` patterns (the `.agent/risk.json` `paths[]` match) are unaffected by `-f`.
# The suite's cwd-seeded case + its mutation control (delete the `-f`) keep this true.

set -fuo pipefail

SELF="classify-risk.sh"

# ---------------------------------------------------------------------------
# The heuristic as DATA — the classifier and --kind-table both read these lists (no second copy).
# ---------------------------------------------------------------------------
GENERIC_GLOBS='*auth* *authz* *security* *crypto* *secret* *token* *payment* migrations/ *migration*'
GENERIC_DIRS='.github/workflows/ hooks/ agents/ commands/ command-parts/ skills/'
GENERIC_WORDS='workflow automation orchestration'
# Trusted-root surfaces — the files that carry the rules a PR is judged by. PLAIN words (no `*`, `?`
# or `[`), so noglob never touches them: the any-depth rule is a `case` on `*/<name>` built in code.
TRUSTED_ROOT_ANYDEPTH='CLAUDE.md AGENTS.md REVIEW.md CLAUDE.local.md'
TRUSTED_ROOT_ROOTONLY='.claude/ .mcp.json .agent/rules/ .agent/risk.json .agent/verify.json'
SIZE_LINES=400
SIZE_FILES=15
REASON_CAP=20

# ---------------------------------------------------------------------------
# --kind-table — the single source of the heuristic table. docs/RESULT_SCHEMAS.md carries the ONE
# committed copy between <!-- risk-table:begin --> / <!-- risk-table:end --> (byte-for-byte, gated
# by the test suite); the lens and the loop point here instead of restating. Builtins only.
# ---------------------------------------------------------------------------
list_as_code() {  # "a b c" -> "`a`, `b`, `c`"
  local out="" w
  for w in $1; do out="${out:+$out, }\`$w\`"; done
  printf '%s' "$out"
}
print_kind_table() {
  printf '%s\n' \
    '| Branch | Rule | Scope | Reason prefix |' \
    '|--------|------|-------|---------------|' \
    "| (a) security / financial / migration | $(list_as_code "$GENERIC_GLOBS") | changed path OR changed line, case-insensitive substring | \`path:\` / \`content:\` |" \
    "| (b) workflow / orchestration surfaces | $(list_as_code "$GENERIC_DIRS") | changed path under that directory (at the root or anywhere below) | \`path:\` |" \
    "| (b) workflow / orchestration words | $(list_as_code "$GENERIC_WORDS") | changed path OR changed line, case-insensitive substring | \`path:\` / \`content:\` |" \
    "| (c) size | \`changed_lines > $SIZE_LINES\` | added+removed lines of \`git diff <base>...<head>\` (\`+++\`/\`---\` headers excluded) | \`size:\` |" \
    "| (c) size | \`changed_files > $SIZE_FILES\` | line count of \`git diff <base>...<head> --name-only\` | \`size:\` |" \
    "| trusted-root (instruction / config) | any depth: $(list_as_code "$TRUSTED_ROOT_ANYDEPTH"); repo root only: $(list_as_code "$TRUSTED_ROOT_ROOTONLY") | changed path on either side of a rename (\`--no-renames\`), case-insensitive: exact path (a \`/\`-terminated entry also without its \`/\`), under a \`/\`-terminated directory, an ancestor of a root-only entry, or exact basename for the any-depth names — never a substring | \`trusted-root:\` |" \
    '| project (add-only) | `.agent/risk.json` at `<base_ref>` `paths[]` (`case` globs — `*`/`**` match across `/`) and `content[]` (literal words, case-insensitive) | changed path / changed line; read from `<base_ref>` only, never the working tree; NO `exclude` key (R5) | `project:` |'
}

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
base=""
head=""
root="."
npos=0
bad_args=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kind-table) print_kind_table; exit 0 ;;
    --root)
      if [ $# -lt 2 ]; then bad_args="--root needs a directory argument"; break; fi
      root="$2"; shift 2 ;;
    --root=*) root="${1#--root=}"; shift ;;
    -h|--help)
      printf 'usage: %s <base_ref> <head_ref> [--root <dir>] | --kind-table\n' "$SELF" >&2
      exit 0 ;;
    --*) bad_args="unknown option $1"; break ;;
    *)
      if [ "$npos" -eq 0 ]; then base="$1"; npos=1
      elif [ "$npos" -eq 1 ]; then head="$1"; npos=2
      else bad_args="unexpected argument"; break
      fi
      shift ;;
  esac
done
[ -z "$bad_args" ] && [ "$npos" -lt 2 ] && bad_args="need <base_ref> and <head_ref>"
[ -z "$bad_args" ] && [ -z "$root" ] && bad_args="--root must not be empty"
[ -z "$bad_args" ] && { [ -z "$base" ] || [ -z "$head" ]; } && bad_args="refs must not be empty"
root="${root%/}"
[ -z "$root" ] && root="/"

# ---------------------------------------------------------------------------
# The ONE shell-templated object shape (used only when jq may be absent). Fixed literals only.
# ---------------------------------------------------------------------------
emit_templated() {
  # $1 = reason token (a fixed literal from this file, never caller text)
  printf '{"high_risk":null,"reasons":["unclassifiable: %s"],"changed_files":0,"changed_lines":0,"source":"%s"}\n' "$1" "$SELF"
  exit 0
}

if [ -n "$bad_args" ]; then
  printf '%s: unclassifiable — bad_args (%s)\n' "$SELF" "$bad_args" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -n -c --arg s "$SELF" \
      '{high_risk: null, reasons: ["unclassifiable: bad_args"], changed_files: 0, changed_lines: 0, source: $s}'
    exit 0
  fi
  emit_templated "bad_args"
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '%s: unclassifiable — jq_missing (jq is required to build the result object)\n' "$SELF" >&2
  emit_templated "jq_missing"
fi

emit_unclassifiable() {
  # $1 = reason token, $2 = detail (stderr only — never reaches the JSON)
  printf '%s: unclassifiable — %s (%s)\n' "$SELF" "$1" "$2" >&2
  jq -n -c --arg r "unclassifiable: $1" --arg s "$SELF" \
    '{high_risk: null, reasons: [$r], changed_files: 0, changed_lines: 0, source: $s}'
  exit 0
}

# ---------------------------------------------------------------------------
# The diff (read-only, git -C — never cd)
# ---------------------------------------------------------------------------
if ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit_unclassifiable "not_a_git_repo" "root=$root"
fi
for ref in "$base" "$head"; do
  if ! git -C "$root" rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1; then
    emit_unclassifiable "bad_ref" "ref=$ref root=$root"
  fi
done

tmp="$(mktemp -d 2>/dev/null)" || emit_unclassifiable "git_failed" "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
if ! git -C "$root" diff --name-only "$base...$head" > "$tmp/paths" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
if ! git -C "$root" diff "$base...$head" > "$tmp/diff" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
# Changed lines: `+`/`-` lines minus the `+++`/`---` file headers.
grep -E '^[+-]' "$tmp/diff" | grep -vE '^(\+\+\+|---)' > "$tmp/lines" || true
changed_files="$(grep -c . "$tmp/paths" || true)"; changed_files="${changed_files:-0}"
changed_lines="$(grep -c . "$tmp/lines" || true)"; changed_lines="${changed_lines:-0}"
tr '[:upper:]' '[:lower:]' < "$tmp/paths" > "$tmp/lpaths"

# ---------------------------------------------------------------------------
# Matching helpers. Reasons accumulate one per line in $tmp/reasons; dedupe + cap at the end.
# ---------------------------------------------------------------------------
reason() { printf '%s\n' "$1" >> "$tmp/reasons"; }
: > "$tmp/reasons"

# content_hits <literal> -> number of changed lines containing it, case-insensitive (0 on empty)
content_hits() {
  [ -z "$1" ] && { echo 0; return; }
  local n; n="$(grep -icF -- "$1" "$tmp/lines" || true)"; echo "${n:-0}"
}

# strip_stars — `*auth*` -> `auth` (the literal the substring match uses)
strip_stars() { local s="$1"; s="${s#"${s%%[!*]*}"}"; s="${s%"${s##*[!*]}"}"; printf '%s' "$s"; }

# (a) + (b)-words: path OR content, case-insensitive substring.
for pat in $GENERIC_GLOBS $GENERIC_WORDS; do
  lit="$(strip_stars "$pat" | tr '[:upper:]' '[:lower:]')"
  [ -z "$lit" ] && continue
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in *"$lit"*) reason "path: $p matched $pat" ;; esac
  done < "$tmp/lpaths"
  n="$(content_hits "$lit")"
  [ "$n" -gt 0 ] && reason "content: $n changed line(s) matched $pat"
done

# (b)-dirs: the directory at the path root or anywhere below.
for d in $GENERIC_DIRS; do
  ld="$(printf '%s' "$d" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in "$ld"*|*"/$ld"*) reason "path: $p matched $d" ;; esac
  done < "$tmp/lpaths"
done

# (c) size.
[ "$changed_lines" -gt "$SIZE_LINES" ] && reason "size: changed_lines $changed_lines > $SIZE_LINES"
[ "$changed_files" -gt "$SIZE_FILES" ] && reason "size: changed_files $changed_files > $SIZE_FILES"

# ---------------------------------------------------------------------------
# trusted-root — instruction / config surfaces. Its own path list: `--no-renames` reports BOTH
# sides of a rename (a root-only `.mcp.json` moved to `config/mcp.json` must still be seen), and
# `-z` keeps paths verbatim (no core.quotePath quoting that would hide a basename).
# ---------------------------------------------------------------------------
if ! git -C "$root" diff --name-only --no-renames -z "$base...$head" > "$tmp/trpaths" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
tr '[:upper:]' '[:lower:]' < "$tmp/trpaths" > "$tmp/ltrpaths"
TR_ANY_L="$(printf '%s' "$TRUSTED_ROOT_ANYDEPTH" | tr '[:upper:]' '[:lower:]')"
TR_ROOT_L="$(printf '%s' "$TRUSTED_ROOT_ROOTONLY" | tr '[:upper:]' '[:lower:]')"

# trusted_root_hit <lowercased path> — 0 when it is a trusted-root surface. Exact / prefix / basename
# / ancestor `case` arms only, never a substring. The exact and ancestor arms close the symlink
# shape: a PR adding `cfg/settings.json` plus a symlink from the root config directory to `cfg`
# diffs as the bare, `/`-less directory path (mode 120000), never as a path under it.
trusted_root_hit() {
  local n
  for n in $TR_ANY_L; do
    case "$1" in "$n"|*/"$n") return 0 ;; esac
  done
  local m
  for n in $TR_ROOT_L; do
    m="${n%/}"
    # exact path — also the bare `/`-less form of a directory entry (a symlink or file)
    case "$1" in "$m") return 0 ;; esac
    # an ANCESTOR of an entry (a `.agent` symlink replaces `.agent/rules/`, `.agent/verify.json`, ...)
    case "$m" in "$1"/*) return 0 ;; esac
    # under a `/`-terminated directory entry
    case "$n" in */) case "$1" in "$n"*) return 0 ;; esac ;; esac
  done
  return 1
}
while IFS= read -r -d '' p; do
  [ -z "$p" ] && continue
  trusted_root_hit "$p" && reason "trusted-root: $p"
done < "$tmp/ltrpaths"

# ---------------------------------------------------------------------------
# Project extension — .agent/risk.json at <base_ref> (add-only; strict shape; never trusted as code).
# Read from the BASE ref only — the working tree and <head_ref> are the PR's own and never read.
# ---------------------------------------------------------------------------
# Presence probe: `ls-tree` reads trees only, so it separates "absent" (exit 0, empty output) from
# "git failed" (non-zero ⇒ unclassifiable) — a failed probe is never read as absence.
rj_label="$base:.agent/risk.json"
if ! git -C "$root" ls-tree -z --full-tree --name-only "$base" -- .agent/risk.json > "$tmp/rjls" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "base risk.json probe failed: $(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
if [ -s "$tmp/rjls" ]; then
  rj="$tmp/base-risk.json"
  if ! git -C "$root" show "$base:.agent/risk.json" > "$rj" 2>"$tmp/err"; then
    emit_unclassifiable "git_failed" "base risk.json unreadable: $(head -c 200 "$tmp/err" | tr '\n' ' ')"
  fi
  shape="$(jq -r '
    if type != "object" then "malformed"
    elif (has("schema_version") and .schema_version != 1) then "malformed"
    elif (has("paths") and ((.paths|type) != "array" or any(.paths[]; type != "string"))) then "malformed"
    elif (has("content") and ((.content|type) != "array" or any(.content[]; type != "string"))) then "malformed"
    else "ok" end' "$rj" 2>/dev/null || echo malformed)"
  if [ "$shape" != "ok" ]; then
    printf '%s: risk_json_malformed — %s ignored (expected {"schema_version":1,"paths":[..],"content":[..]}); generic heuristic only\n' "$SELF" "$rj_label" >&2
  else
    if jq -e 'has("exclude")' "$rj" >/dev/null 2>&1; then
      printf '%s: risk_json_exclude_ignored — %s carries an "exclude" key; projects may only ADD surfaces (R5), the key is ignored\n' "$SELF" "$rj_label" >&2
    fi
    # paths[]: case patterns against the lowercased changed path — matched with `case`, never eval.
    while IFS= read -r g; do
      [ -z "$g" ] && continue
      lg="$(printf '%s' "$g" | tr '[:upper:]' '[:lower:]')"
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        # shellcheck disable=SC2254
        case "$p" in $lg) reason "project: $p matched $g" ;; esac
      done < "$tmp/lpaths"
    done < <(jq -r '.paths // [] | .[]' "$rj")
    # content[]: literal words, case-insensitive (grep -iF — never a regex).
    while IFS= read -r w; do
      [ -z "$w" ] && continue
      n="$(content_hits "$w")"
      [ "$n" -gt 0 ] && reason "project: $n changed line(s) matched $w"
    done < <(jq -r '.content // [] | .[]' "$rj")
  fi
fi

# ---------------------------------------------------------------------------
# Dedupe, cap, emit.
# ---------------------------------------------------------------------------
awk '!seen[$0]++' "$tmp/reasons" > "$tmp/uniq"
total="$(grep -c . "$tmp/uniq" || true)"; total="${total:-0}"
if [ "$total" -gt "$REASON_CAP" ]; then
  head -n "$REASON_CAP" "$tmp/uniq" > "$tmp/capped"
  printf '+%s more\n' "$((total - REASON_CAP))" >> "$tmp/capped"
else
  cp "$tmp/uniq" "$tmp/capped"
fi
if [ "$total" -gt 0 ]; then hr=true; else hr=false; fi

jq -n -c --argjson hr "$hr" --arg raw "$(cat "$tmp/capped")" \
  --argjson cf "$changed_files" --argjson cl "$changed_lines" --arg s "$SELF" \
  '{high_risk: $hr, reasons: ($raw | split("\n") | map(select(length > 0))), changed_files: $cf, changed_lines: $cl, source: $s}'
exit 0
