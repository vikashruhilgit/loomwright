#!/usr/bin/env bash
# verify-provides.sh — the ONE deterministic implementation of the three `provides:` checks
# (`file` / `symbol` / `type`) that every consumer of a WORKER_RESULT runs against the tree the
# worker wrote to. Disk is authoritative: the worker's self-reported `outputs_verified` /
# `outputs_gap` is an INPUT it cross-checks (and records a `provides_mismatch` on), never the
# thing that decides the gate.
#
# Usage:
#   verify-provides.sh <brief> <subtask-id> [--root <dir>]     # default --root .
#   verify-provides.sh --kind-table                            # print the 3-row markdown check table
#
# <subtask-id> is the bare token the brief's contract anchor names — the `N` in `# Subtask N …` /
# `### Subtask N …` / `subtask_N:` (`1`, `12`; on the Single-Agent Path the brief's single anchor,
# `1`). It is NOT the state.md task_id, a Beads id or a slug: those return `subtask_not_found`,
# which every consumer routes to a checkpoint (D1) — so the stderr line for that reason lists the
# anchors the brief actually carries.
#
# Output (ONE JSON object on stdout, always exit 0):
#   {"subtask_id":"<id>",
#    "outputs_verified":[{"kind":..,"path":..,"name"?:..,"status":"present"|"missing","check_run":"<command> (exit N)"}],
#    "outputs_gap":"<path or path:name, comma-separated, or \"\">",
#    "source":"verify-provides.sh"}
#   — `outputs_gap` is byte-identical to the worker's own format (agents/worker.md Step 5.5 item 4:
#   "src/foo.ts:Bar, src/baz.ts"). When the brief cannot be read, the subtask is not in it, or it has
#   no contract block at all:
#   {"subtask_id":"<id>","status":"unverifiable","reason":"brief_unreadable"|"subtask_not_found"|"no_contracts","source":"verify-provides.sh"}
#   plus the reason on stderr. A missing `jq` is a fourth reason, `jq_missing` — the ONE
#   shell-templated object in this file (jq is by definition absent); it carries `subtask_id` only
#   when the id matches ^[[:alnum:]_-]+$, otherwise the key is omitted (argv is caller text and must
#   never reach the JSON unescaped). Every other object is built with `jq --arg`.
#
# Failure-mode split (CLAUDE.md §"Failure-Mode Invariants"): this script is a fail-SAFE EMITTER —
# it always exits 0, never writes, never `cd`s into --root, never executes brief content (no eval /
# source). Its CONSUMERS fail CLOSED: a `missing` item, or an `unverifiable` result the consumer
# cannot route, reaches the existing adjudication EXECUTE_CHECKPOINT (agents/execute-manager.md
# §"v12 outputs_verified gate"; agents/supervisor.md Single-Agent / Sequential gates). Decision D1
# (brief 2026-09-13-manager-reverifies-provides): `brief_unreadable` / `subtask_not_found` /
# `jq_missing` ⇒ checkpoint on every path; `no_contracts` ⇒ checkpoint on the `job:` path unless the
# brief's `## Environment` declares `legacy_brief: true`, and on legacy / no-brief runs the consumer
# records `provides_unverifiable` and falls through to the worker's self-report (Plan Reviewer
# Criterion 12's own opt-out, reused — not a new flag).
#
# Brief parser tolerance (measured over real Launch Pad briefs): the contracts heading is matched
# case-insensitively at ANY `#` depth, the YAML may sit in a ```yaml fence or be raw, and a
# subtask is anchored by a `# Subtask N …` YAML comment, a `### Subtask N …` markdown heading, or a
# `subtask_N:` key. Entries are `- {kind: "file", path: "x", name: "y"}` (quotes optional, trailing
# `# comment` after the closing `}` stripped). The `provides:` list ends at the next top-level key
# (`requires:` / `lanes:` / `external_requires:`), the next anchor, a heading, or the fence end.
# `provides: []` — or a `provides:` with no parsable entries — yields `[]` + `""` (logged to stderr).
#
# HONEST LIMITS: the `symbol` check is `grep -nE -- '<escaped name>'` over the whole file — any line
# containing the name passes, including a comment or a prose mention; there is no semantic check
# and no "is it exported / is it the right kind" check. `type` is the same grep with a keyword
# prefix. Portable ERE only (no `\s` / `\b`); bash 3.2 / BSD userland safe.
#
# Co-located static suite: test-verify-provides.sh.

set -uo pipefail

SELF="verify-provides.sh"

# ---------------------------------------------------------------------------
# --kind-table — the single source of the three check rows. docs/RESULT_SCHEMAS.md carries the ONE
# committed copy between <!-- kind-table:begin --> / <!-- kind-table:end --> (byte-for-byte, gated by
# the test suite); agents/worker.md and agents/execute-manager.md point here instead of restating.
# Builtins only (printf) so it also works on a jq-less / PATH-less host.
# ---------------------------------------------------------------------------
print_kind_table() {
  printf '%s\n' \
    '| `kind` | Verification command | PRESENT condition |' \
    '|--------|----------------------|-------------------|' \
    '| `file` | `test -f <root>/<path>` | exit 0 |' \
    '| `symbol` | `grep -nE -- '"'"'<escaped name>'"'"' <root>/<path>` | any match (exit 0) |' \
    '| `type` | `grep -nE -- '"'"'(type\|interface\|class\|enum)[[:space:]]+<escaped name>([^[:alnum:]_]\|$)'"'"' <root>/<path>` | any match (exit 0) |'
}

# ---------------------------------------------------------------------------
# Arg parse
# ---------------------------------------------------------------------------
brief=""
id=""
root="."
have_brief=0
have_id=0
while [ $# -gt 0 ]; do
  case "$1" in
    --kind-table) print_kind_table; exit 0 ;;
    --root)
      if [ $# -lt 2 ]; then
        printf '%s: --root needs a directory argument\n' "$SELF" >&2
        exit 0
      fi
      root="$2"; shift 2 ;;
    --root=*) root="${1#--root=}"; shift ;;
    -h|--help)
      printf 'usage: %s <brief> <subtask-id> [--root <dir>] | --kind-table\n' "$SELF" >&2
      exit 0 ;;
    *)
      if [ "$have_brief" -eq 0 ]; then brief="$1"; have_brief=1
      elif [ "$have_id" -eq 0 ]; then id="$1"; have_id=1
      else printf '%s: unexpected argument %s (ignored)\n' "$SELF" "$1" >&2
      fi
      shift ;;
  esac
done
root="${root%/}"
[ -z "$root" ] && root="/"

# ---------------------------------------------------------------------------
# jq presence — the one shell-templated object. Builtins only past this point until jq is known.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  printf '%s: unverifiable — jq_missing (jq is required to build the result object)\n' "$SELF" >&2
  case "$id" in
    ''|*[![:alnum:]_-]*)
      printf '{"status":"unverifiable","reason":"jq_missing","source":"%s"}\n' "$SELF" ;;
    *)
      printf '{"subtask_id":"%s","status":"unverifiable","reason":"jq_missing","source":"%s"}\n' "$id" "$SELF" ;;
  esac
  exit 0
fi

emit_unverifiable() {
  # $1 = reason
  printf '%s: unverifiable — %s (brief=%s subtask=%s)\n' "$SELF" "$1" "$brief" "$id" >&2
  jq -n -c --arg id "$id" --arg r "$1" --arg s "$SELF" \
    '{subtask_id: $id, status: "unverifiable", reason: $r, source: $s}'
  exit 0
}

# ---------------------------------------------------------------------------
# Brief readable?
# ---------------------------------------------------------------------------
if [ "$have_brief" -eq 0 ] || [ "$have_id" -eq 0 ]; then
  printf 'usage: %s <brief> <subtask-id> [--root <dir>] | --kind-table\n' "$SELF" >&2
  emit_unverifiable "brief_unreadable"
fi
if [ ! -f "$brief" ] || [ ! -r "$brief" ]; then
  emit_unverifiable "brief_unreadable"
fi

# ---------------------------------------------------------------------------
# ONE awk pass over the brief. Prints a first status line — FOUND / EMPTY / NOT_FOUND<TAB><anchors
# seen> / NO_CONTRACTS — then, for FOUND, one `kind<TAB>path<TAB>name` line per provides entry.
# The id is passed as DATA (-v) and matched with index()/substr(), never interpolated into a regex.
# ---------------------------------------------------------------------------
parse_brief() {
  awk -v want="$1" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    # id_here(rest): rest (lowercased) starts with the wanted id, followed by a non-alnum or end.
    function id_here(rest,   c) {
      if (index(rest, lwant) != 1) return 0
      c = substr(rest, length(lwant) + 1, 1)
      if (c ~ /[[:alnum:]]/) return 0
      return 1
    }
    # note_anchor(line, pos): remember the ORIGINAL-case token an anchor names (for the
    # subtask_not_found stderr line); the umbrella headings are not subtask anchors.
    function note_anchor(line, pos,   o, l) {
      o = substr(line, pos)
      if (!match(o, /^[[:alnum:]_-]+/)) return
      o = substr(o, RSTART, RLENGTH); l = tolower(o)
      if (l == "contracts" || l == "structure" || (o in seen)) return
      seen[o] = 1; anchors = (anchors == "" ? o : anchors ", " o)
    }
    # anchor_kind(line): 0 = not an anchor; 1 = anchor for SOME subtask; 2 = anchor for OURS.
    # Forms: `# Subtask N …` (YAML comment) / `### Subtask N …` (heading) / `subtask_N:` (key).
    function anchor_kind(line,   t, rest, pos) {
      t = tolower(line)
      if (match(t, /^[[:space:]]*#+[[:space:]]*subtask[[:space:]_-]*[[:alnum:]]/)) {
        pos = RSTART + RLENGTH - 1; rest = substr(t, pos)
        note_anchor(line, pos)
        return id_here(rest) ? 2 : 1
      }
      if (match(t, /^[[:space:]]*subtask[[:space:]_-]*[[:alnum:]]/)) {
        pos = RSTART + RLENGTH - 1; rest = substr(t, pos)
        if (rest !~ /^[^:]*:/) return 0
        note_anchor(line, pos)
        return id_here(rest) ? 2 : 1
      }
      return 0
    }
    # field(entry, key): value of `key: value` inside a flow mapping; quotes optional.
    function field(entry, key,   rest, q, e, v) {
      if (!match(entry, "(^|[{,])[[:space:]]*" key "[[:space:]]*:[[:space:]]*")) return ""
      rest = substr(entry, RSTART + RLENGTH)
      q = substr(rest, 1, 1)
      if (q == "\"" || q == "\047") {
        e = index(substr(rest, 2), q)
        if (e == 0) return trim(substr(rest, 2))
        return substr(rest, 2, e - 1)
      }
      v = rest
      if (match(v, /[,}]/)) v = substr(v, 1, RSTART - 1)
      return trim(v)
    }
    BEGIN { lwant = tolower(want); infence = 0; inside = 0; inprov = 0; found = 0; any = 0; n = 0; empty = 0; anchors = "" }
    {
      line = $0
      # Fence toggle. Closing the fence while inside our block ends the provides list.
      if (line ~ /^[[:space:]]*(```|~~~)/) {
        if (infence) { infence = 0; if (inside) { inside = 0; inprov = 0 } }
        else { infence = 1 }
        next
      }
      t = tolower(line)
      if (!infence && t ~ /^#+[[:space:]]*subtask[[:space:]]+contracts/) { any = 1 }
      if (t ~ /^[[:space:]]*provides[[:space:]]*:/) any = 1
      ak = anchor_kind(line)
      if (!infence && line ~ /^#+[[:space:]]/ && ak == 0) {
        # a markdown heading outside a fence ends our block
        if (inside) { inside = 0; inprov = 0 }
        next
      }
      if (ak == 2 && !found) { found = 1; inside = 1; inprov = 0; next }
      if (ak >= 1 && inside) { inside = 0; inprov = 0; next }
      if (!inside) next
      if (!inprov) {
        if (t ~ /^[[:space:]]*provides[[:space:]]*:/) {
          inprov = 1
          rest = line; sub(/^[[:space:]]*[Pp][Rr][Oo][Vv][Ii][Dd][Ee][Ss][[:space:]]*:[[:space:]]*/, "", rest)
          if (rest ~ /^\[[[:space:]]*\]/) { empty = 1; inside = 0; inprov = 0 }
        }
        next
      }
      # inside provides:
      if (line ~ /^[[:space:]]*-[[:space:]]*\{/) {
        entry = line
        sub(/^[[:space:]]*-[[:space:]]*/, "", entry)
        if (match(entry, /\}[[:space:]]*#/)) entry = substr(entry, 1, RSTART)
        else if (match(entry, /\}[^}]*$/)) entry = substr(entry, 1, RSTART)
        k = field(entry, "kind"); p = field(entry, "path"); nm = field(entry, "name")
        gsub(/\t/, " ", k); gsub(/\t/, " ", p); gsub(/\t/, " ", nm)
        if (k != "" || p != "") { n++; out[n] = k "\t" p "\t" nm }
        next
      }
      if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) next   # comment / blank inside the list
      if (line ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:/) { inside = 0; inprov = 0; next }  # next top-level key
      next
    }
    END {
      if (!found) { print (any ? "NOT_FOUND\t" anchors : "NO_CONTRACTS"); exit 0 }
      if (n == 0) { print "EMPTY"; exit 0 }
      print "FOUND"
      for (i = 1; i <= n; i++) print out[i]
    }
  ' "$brief"
}

# ere_escape — make a literal name safe for `grep -E`. bash 3.2 / BSD sed safe: backslashes doubled
# first, then every other ERE special escaped via a bracket expression with `]` first. `.` must NOT
# directly follow `[` — BSD sed reads `[.` as the start of a collating symbol and errors out.
ere_escape() {
  printf '%s\n' "$1" | sed -e 's/\\/\\\\/g' -e 's/[][*.^$+?(){}|]/\\&/g'
}

# grep_literal <pattern> <file> — sets rc; an EMPTY pattern is refused (grep -E '' matches every
# line, which would turn an escaping failure or an empty name into a silent false `present`).
grep_literal() {
  if [ -z "$1" ]; then rc=1; return; fi
  grep -nE -- "$1" "$2" >/dev/null 2>&1; rc=$?
}

TAB="$(printf '\t')"
status=""
anchors=""
entries='[]'
gap=""
line_no=0
parse_ok=1

while IFS= read -r line; do
  line_no=$((line_no + 1))
  if [ "$line_no" -eq 1 ]; then
    status="${line%%"$TAB"*}"
    anchors="${line#*"$TAB"}"; [ "$anchors" = "$line" ] && anchors=""
    continue
  fi
  kind="${line%%"$TAB"*}"
  rest="${line#*"$TAB"}"
  path="${rest%%"$TAB"*}"
  name="${rest#*"$TAB"}"
  [ "$rest" = "$path" ] && name=""

  case "$path" in
    /*) full="$path" ;;
    *)  full="$root/$path" ;;
  esac

  rc=0
  check_run=""
  case "$kind" in
    file)
      test -f "$full"; rc=$?
      check_run="test -f $full (exit $rc)"
      ;;
    symbol|type)
      esc="$(ere_escape "$name")"
      if [ -z "$name" ] || [ -z "$esc" ]; then
        rc=1
        check_run="grep -nE -- '' $full refused: empty name or escape failure (exit 1)"
        printf '%s: entry %s (%s) has an empty/unescapable name — reported missing\n' "$SELF" "$path" "$kind" >&2
      else
        if [ "$kind" = "symbol" ]; then pat="$esc"
        else pat="(type|interface|class|enum)[[:space:]]+${esc}([^[:alnum:]_]|\$)"
        fi
        grep_literal "$pat" "$full"
        check_run="grep -nE -- '$pat' $full (exit $rc)"
      fi
      ;;
    *)
      rc=1
      check_run="unsupported kind '$kind' (exit 1)"
      printf '%s: entry %s has unsupported kind %s — reported missing\n' "$SELF" "$path" "$kind" >&2
      ;;
  esac

  if [ "$rc" -eq 0 ]; then st="present"; else st="missing"; fi

  entries="$(jq -c --arg k "$kind" --arg p "$path" --arg n "$name" --arg s "$st" --arg c "$check_run" \
    '. + [ ({kind: $k, path: $p} + (if $k == "file" then {} else {name: $n} end) + {status: $s, check_run: $c}) ]' \
    <<<"$entries")" || parse_ok=0

  if [ "$st" = "missing" ]; then
    if [ "$kind" = "file" ]; then item="$path"; else item="$path:$name"; fi
    gap="${gap:+$gap, }$item"
  fi
done < <(parse_brief "$id")

case "$status" in
  NO_CONTRACTS) emit_unverifiable "no_contracts" ;;
  NOT_FOUND)
    printf '%s: subtask %s not in brief — anchors found: %s\n' "$SELF" "$id" "${anchors:-(none)}" >&2
    emit_unverifiable "subtask_not_found"
    ;;
  EMPTY)
    printf '%s: subtask %s has an empty provides: list (nothing to verify)\n' "$SELF" "$id" >&2
    entries='[]'; gap=""
    ;;
  FOUND) ;;
  *)            emit_unverifiable "brief_unreadable" ;;
esac

if [ "$parse_ok" -ne 1 ]; then
  printf '%s: internal jq error while building outputs_verified\n' "$SELF" >&2
  emit_unverifiable "brief_unreadable"
fi

jq -n -c --arg id "$id" --argjson ov "$entries" --arg gap "$gap" --arg s "$SELF" \
  '{subtask_id: $id, outputs_verified: $ov, outputs_gap: $gap, source: $s}'
exit 0
