#!/usr/bin/env bash
# classify-risk.sh — the ONE deterministic implementation of the high-risk-diff heuristic that
# `skills/self-heal-advisory/SKILL.md` §"Advisory red-team lens" used to carry as prompt pseudo-code
# and that `automate-helpers.sh gate-eval` now judges as its sixth fail-CLOSED condition. Read-only:
# it never writes, never `cd`s into --root (every git call is `git -C "$root"`), never executes any
# content it reads (no eval / source — project patterns are matched with `case` and `grep -F` only).
#
# Usage:
#   classify-risk.sh <base_ref> <head_ref> [--root <dir>]   # default --root .
#   classify-risk.sh --paths <file> [--root <dir>]          # classify a path LIST (no diff), see below
#   classify-risk.sh --kind-table                           # print the heuristic as a markdown table
#
# --paths mode (gate-auto.sh's risk read for a Launch Pad brief, which has a File Impact Map but no
# diff): <file> holds one repo-relative path per line. The path branches of (a) and (b), trusted-root and the project `.agent/risk.json` `paths[]`
# (read at HEAD — the committed tree, never the working tree) run over the listed paths; content and
# size cannot be judged from a path list and emit no reason (`changed_lines` is 0, `changed_files` the
# number of distinct listed paths). Same object shape and `source`. An unreadable list ⇒
# `unclassifiable: paths_unreadable`, an empty one ⇒ `unclassifiable: paths_empty`, a line holding any
# byte outside the allow-list [A-Za-z0-9._/+@-] (a decorated cell such as "`CLAUDE.md` (40)",
# "**CLAUDE.md**", a `:<line>` suffix, a markdown link or a `|` cell — not a bare path), a leading `/`,
# an empty `//` or `.`/`..` segment, or a line wrapped in `_…_` emphasis ⇒
# `unclassifiable: paths_malformed` (null all three: a list that cannot be read is never low-risk).
# A real path with another legal byte (`,` `=` `~` `%` space, non-ASCII) also reads null: the
# consumer then asks, the safe direction (this repo's `git ls-files` has none). It adds no exclude, flag or config to lower risk. The refs
# mode above is untouched by it: same code path, same output, byte for byte.
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
#   -- .agent .agent/risk.json` succeeds and lists no `.agent/risk.json` entry) ⇒ silent
#   generic-only; a FAILED probe (non-zero exit) ⇒ `unclassifiable: git_failed` (null), never
#   read as absence. The file is
#   read ONLY from `<base_ref>` (`git -C <root> show`), never from the working tree
#   or `<head_ref>`, so a PR cannot drop an entry and change the guarded path in one diff; `--root`
#   picks the repository only. A present blob that `git show` cannot read ⇒
#   `unclassifiable: git_failed` (null), never a silent drop of the project's entries. A base
#   `.agent` or `.agent/risk.json` that is a SYMLINK (tree mode 120000) ⇒
#   `unclassifiable: risk_json_symlink` (null): git reads never follow an in-tree link, and
#   following it could resolve into the PR's own working tree, so the owner's entries are
#   unreadable — fail CLOSED rather than silently absent. A base `.agent` that is a SUBMODULE
#   (gitlink, mode 160000) ⇒ `unclassifiable: risk_json_gitlink` (null) for the same reason. Only
#   the exact paths `.agent` and `.agent/risk.json` are judged; another symlink under `.agent/` is
#   not.
#
# Failure-mode split (CLAUDE.md §"Failure-Mode Invariants"): this script is a fail-SAFE EMITTER —
# it always exits 0. `high_risk: null` + `reasons: ["unclassifiable: <reason>"]` + the reason on
# stderr is emitted when the diff cannot be classified (bad_args, jq_missing, not_a_git_repo,
# bad_ref, git_failed, risk_json_symlink, risk_json_gitlink; --paths adds paths_unreadable,
# paths_empty and paths_malformed). Its CONSUMERS fail CLOSED: `gate-eval` parks on
# anything but an explicit `false` (`PARK: high_risk_diff`) with no override of any kind, and the
# Phase 4.5 lens treats `null` as "spawn the advisory pass" (the safe direction for an advisory lens is to run it).
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
# A project that deliberately commits `.agent` (or `.agent/risk.json`) as a symlink gets
# `unclassifiable: risk_json_symlink` on EVERY diff — the gate parks until the file is a regular blob.
# Likewise a project whose `.agent` is a submodule gets `unclassifiable: risk_json_gitlink` on EVERY
# diff — the gate parks until `.agent` is a regular directory in the repository itself.
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
paths_mode=""   # non-empty ⇒ --paths mode (D6): classify a path LIST, not a diff
paths_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kind-table) print_kind_table; exit 0 ;;
    --root)
      if [ $# -lt 2 ]; then bad_args="--root needs a directory argument"; break; fi
      root="$2"; shift 2 ;;
    --root=*) root="${1#--root=}"; shift ;;
    --paths)
      if [ $# -lt 2 ]; then bad_args="--paths needs a file argument"; break; fi
      paths_mode=1; paths_file="$2"; shift 2 ;;
    --paths=*) paths_mode=1; paths_file="${1#--paths=}"; shift ;;
    -h|--help)
      printf 'usage: %s <base_ref> <head_ref> [--root <dir>] | --paths <file> [--root <dir>] | --kind-table\n' "$SELF" >&2
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
if [ -n "$paths_mode" ]; then
  [ -z "$bad_args" ] && [ "$npos" -gt 0 ] && bad_args="--paths takes no <base_ref> <head_ref>"
  [ -z "$bad_args" ] && [ -z "$paths_file" ] && bad_args="--paths must not be empty"
else
  [ -z "$bad_args" ] && [ "$npos" -lt 2 ] && bad_args="need <base_ref> and <head_ref>"
fi
[ -z "$bad_args" ] && [ -z "$root" ] && bad_args="--root must not be empty"
[ -z "$bad_args" ] && [ -z "$paths_mode" ] && { [ -z "$base" ] || [ -z "$head" ]; } && bad_args="refs must not be empty"
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
# --paths mode (D6) reads `.agent/risk.json` at HEAD: the project extension below reads it at "$base",
# so the path list is judged against the committed HEAD tree, never the working tree.
[ -n "$paths_mode" ] && { base="HEAD"; head="HEAD"; }
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
# The refs-mode lines inside the two `if [ -z "$paths_mode" ]` blocks keep their top-level indentation:
# test-classify-risk.sh's mutation controls anchor on it.
if [ -z "$paths_mode" ]; then
if ! git -C "$root" diff --name-only "$base...$head" > "$tmp/paths" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
if ! git -C "$root" diff "$base...$head" > "$tmp/diff" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
# Changed lines: `+`/`-` lines minus the `+++`/`---` file headers.
grep -E '^[+-]' "$tmp/diff" | grep -vE '^(\+\+\+|---)' > "$tmp/lines" || true
else
  # --paths: one repo-relative path per line (CR, surrounding blanks and a leading `./` dropped, blank
  # lines and duplicates skipped). No diff, so no changed lines: the content and size classes are not
  # applicable and emit no reason. An unreadable or empty list cannot be classified ⇒ null.
  [ -f "$paths_file" ] && [ -r "$paths_file" ] || emit_unclassifiable "paths_unreadable" "paths=$paths_file"
  PATHS_NOT_BARE_ERE='[^A-Za-z0-9._/+@-]|^/|//|(^|/)\.\.?(/|$)|^_.*_$'
  sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's|^\./||' "$paths_file" 2>/dev/null \
    | awk 'length($0) > 0 && !seen[$0]++' > "$tmp/paths"
  [ -s "$tmp/paths" ] || emit_unclassifiable "paths_empty" "paths=$paths_file lists no path"
  # ALLOW-LIST, not a denylist of decorations: a line holding any byte outside [A-Za-z0-9._/+@-] (a
  # copied map cell's ` (40)`, backticks, `**bold**`, quotes, `:40`, a markdown link, a `|` cell, a
  # `- ` bullet, non-ASCII) is not a bare path and could hide a high-risk basename from every class
  # ⇒ null. Allowed bytes can still make a non-bare path, so those shapes are refused too: a leading
  # `/` (not repo-relative), an empty `//`, a `.` or `..` segment (`docs/../.mcp.json` would dodge the
  # root-only trusted-root match) and `_…_` emphasis wrapping the whole line. A real path using another legal byte
  # (`,` `=` `~` `%` space) also reads null: the gate then asks, the safe direction. env LC_ALL=C keeps
  # the ranges bytewise in every locale.
  if env LC_ALL=C grep -qE "$PATHS_NOT_BARE_ERE" "$tmp/paths"; then
    emit_unclassifiable "paths_malformed" "paths=$paths_file: $(env LC_ALL=C grep -m1 -E "$PATHS_NOT_BARE_ERE" "$tmp/paths" | head -c 120)"
  fi
  : > "$tmp/lines"
fi
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

# (c) size — refs mode only (a path list has no diff to measure).
[ -z "$paths_mode" ] && [ "$changed_lines" -gt "$SIZE_LINES" ] && reason "size: changed_lines $changed_lines > $SIZE_LINES"
[ -z "$paths_mode" ] && [ "$changed_files" -gt "$SIZE_FILES" ] && reason "size: changed_files $changed_files > $SIZE_FILES"

# ---------------------------------------------------------------------------
# trusted-root — instruction / config surfaces. Its own path list: `--no-renames` reports BOTH
# sides of a rename (a root-only `.mcp.json` moved to `config/mcp.json` must still be seen), and
# `-z` keeps paths verbatim (no core.quotePath quoting that would hide a basename).
# ---------------------------------------------------------------------------
if [ -z "$paths_mode" ]; then
if ! git -C "$root" diff --name-only --no-renames -z "$base...$head" > "$tmp/trpaths" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "$(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
else
  tr '\n' '\000' < "$tmp/paths" > "$tmp/trpaths"   # --paths: the listed paths, NUL-separated like -z
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
# "git failed" (non-zero ⇒ unclassifiable) — a failed probe is never read as absence. When `.agent`
# is a directory the probe lists its direct children (not `.agent` itself); when it is a single
# entry (link, gitlink, file) it lists `.agent` alone. Only the records whose path is EXACTLY
# `.agent` or `.agent/risk.json` are judged — any other child (an unrelated `.agent/notes-link`
# symlink) is ignored. Per mode on those two paths:
#   120000 symlink on either path ⇒ `unclassifiable: risk_json_symlink` (null): `ls-tree` and
#          `git show <base>:<path>` never follow an in-tree link, and following it could resolve
#          into the PR's working tree, so the owner's entries are unreadable — fail CLOSED.
#   160000 gitlink on `.agent` ⇒ `unclassifiable: risk_json_gitlink` (null): a submodule's contents
#          are not in this repository's base tree, so the entries are unreadable — fail CLOSED.
#          A gitlink at `.agent/risk.json` is "present" and its `git show` read fails ⇒ git_failed.
#   040000 tree on `.agent` ⇒ the normal directory case; at `.agent/risk.json` ⇒ present, and the
#          read tree listing is not JSON ⇒ risk_json_malformed (generic-only, stderr).
#   100644/100755 on `.agent` (a regular file) ⇒ no risk.json can exist ⇒ silent generic-only.
rj_label="$base:.agent/risk.json"
if ! git -C "$root" ls-tree -z --full-tree "$base" -- .agent .agent/risk.json > "$tmp/rjls" 2>"$tmp/err"; then
  emit_unclassifiable "git_failed" "base risk.json probe failed: $(head -c 200 "$tmp/err" | tr '\n' ' ')"
fi
rj_present=""
while IFS= read -r -d '' rec; do   # one record per entry: "<mode> <type> <oid>\t<path>"
  rp="${rec#*$'\t'}"
  case "$rp" in .agent|.agent/risk.json) ;; *) continue ;; esac
  case "$rec" in
    120000\ *)
      emit_unclassifiable "risk_json_symlink" "base $rp is a symlink (mode 120000); the committed project entries cannot be read without following it" ;;
  esac
  case "$rp:$rec" in
    .agent:160000\ *)
      emit_unclassifiable "risk_json_gitlink" "base $rp is a submodule (mode 160000); the committed project entries are not in this repository's base tree" ;;
  esac
  [ "$rp" = ".agent/risk.json" ] && rj_present=1
done < "$tmp/rjls"
if [ -n "$rj_present" ]; then
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
