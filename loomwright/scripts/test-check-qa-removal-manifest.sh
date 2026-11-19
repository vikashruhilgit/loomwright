#!/usr/bin/env bash
# test-check-qa-removal-manifest.sh — offline self-test for check-qa-removal-manifest.sh (the per-row
# gate over the reviewed QA-removal manifest).
#
# Modelled on test-check-children-settled.sh: ok()/no() counters, a "RESULT: N passed, M failed" tail,
# exit 1 on any failure, the script found from $BASH_SOURCE, every fixture in its own `mktemp -d` root
# (never the real tree), no git, gh or network. bash 3.2 / BSD userland safe.
#
# Fixture legs (labels quote the brief's `## Pin mutations` rows, so a pin finds its leg by text):
#   usage      — unknown argument, `--expect` with no value, a `--root` that is not a directory and a
#                missing manifest each exit 2 and name the cause.
#   AC1        — no `--expect` on a base-state fixture ⇒ exit 0, every delete/re-point row `pending`,
#                every keep row `ok`, the documented line format, the summary line; the manifest is
#                found at its default path under `--root`.
#   AC2        — a selected `delete` row whose path exists ⇒ exit 1 naming it (plus the passing control
#                once 11b1's deletes are done, so the gate is not trivially red).
#   AC3        — a missing `keep` path, and a `keep` file that lost its kept reference ⇒ exit 1.
#   AC4        — a `re-point` file still naming `qa-executor` at `--expect 12` ⇒ exit 1 naming file +
#                reference; a missing or unreadable re-point file is MISMATCH, never `done`; re-point
#                rows are not checked before 12; the all-done control passes.
#   ordering   — `--expect 11b2` still checks an 11b1 row and does not check a 12 row.
#   AC5        — every refusal its own leg: exit 2, the row (line number + path) named on stderr, no row
#                output — an unknown action / item, a `Row count:` mismatch, a duplicate (path,
#                reference), a keep/re-point conflict, an unknown `--expect` value, and the format
#                refusals (missing / duplicated / malformed `Row count:`, header, separator, cell count,
#                path shape, reference shape, delete-with-reference, re-point-without-reference, empty
#                reason, a split table, zero rows, no `## Rows`).
#   cells      — `\|` in a reference reads as `|`; a reference starting with `-` is a pattern, not an
#                option; a directory row is searched recursively.
#
# Legs over the committed manifest itself (after the fixture legs, before the RESULT tail; read only):
#   real-repo      — no `--expect` over the real tree and the default manifest path ⇒ exit 0, no refusal.
#   AC6 scope rows — the committed manifest has a row for every path the requirement's Scope names.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-qa-removal-manifest.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if [ ! -f "$SCRIPT" ]; then
  no "MISSING script under test: $SCRIPT"
  echo; echo "RESULT: $pass passed, $fail failed"; exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-check-qa-removal-manifest.XXXXXX")" || { echo "mktemp failed"; exit 1; }
cleanup() { chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

# ---- helpers ---------------------------------------------------------------------------------------
# run <root> <args...> — run the checker with --root <root>; sets RC, OUT (stdout file), ERR (stderr file).
OUT="$TMP/out"; ERR="$TMP/err"; RC=0
run() {
  local r="$1"; shift
  RC=0; bash "$SCRIPT" --root "$r" "$@" >"$OUT" 2>"$ERR" || RC=$?
}
# has <file> <fixed line> — the file has exactly that line.
has() { grep -F -x -q -e "$2" -- "$1"; }
# contains <file> <fixed text> — the file contains the text somewhere.
contains() { grep -F -q -e "$2" -- "$1"; }

# expect_rc <label> <want>
expect_rc() {
  if [ "$RC" = "$2" ]; then ok "$1 (exit $2)"; else no "$1 — want exit $2, got $RC; stderr: $(head -3 "$ERR" | tr '\n' ' ')"; fi
}
expect_line() { if has "$OUT" "$2"; then ok "$1 — prints '$2'"; else no "$1 — no line '$2' in: $(tr '\n' '|' <"$OUT")"; fi; }
expect_no_line() { if has "$OUT" "$2"; then no "$1 — unexpected line '$2'"; else ok "$1 — no line '$2'"; fi; }
expect_err() { if contains "$ERR" "$2"; then ok "$1 — stderr names '$2'"; else no "$1 — stderr lacks '$2': $(tr '\n' '|' <"$ERR")"; fi; }
expect_no_rows() { if [ -s "$OUT" ]; then no "$1 — a refused manifest printed rows: $(head -2 "$OUT" | tr '\n' '|')"; else ok "$1 — no row output"; fi; }

# write_manifest <file> <row-count|auto> <table body (rows, one per line)>
write_manifest() {
  local f="$1" n="$2" body="$3"
  if [ "$n" = auto ]; then n="$(printf '%s\n' "$body" | grep -c '^|')"; fi
  mkdir -p "$(dirname "$f")"
  {
    printf '# QA removal manifest (fixture)\n\n'
    printf 'Row count: %s\n\n' "$n"
    printf '## Rows\n\n'
    printf '| path | reference | action | item | reason |\n'
    printf '|---|---|---|---|---|\n'
    printf '%s\n' "$body"
    printf '\n## Rollback\n\nTag `pre-qa-removal`.\n'
  } > "$f"
}

# The base-state rows: every action and item, a keep and a re-point on different references of the
# same file (allowed), a directory row.
BASE_ROWS='| `agents/qa-x.md` | — | delete | 11b1 | old agent |
| `commands/qa-x.md` | — | delete | 11b1 | old command |
| `scripts/verify-run.sh` | — | delete | 11b2 | old verify script |
| `skills/qa-old/` | — | delete | 12 | old skill dir |
| `docs/guide.md` | `qa-executor` | re-point | 12 | names the old agent |
| `scripts/notify.sh` | `qa-strategist` | re-point | 11b2 | name map |
| `scripts/lib.sh` | `qa-strategist` | re-point | 12 | other reference in a kept file |
| `scripts/verify-provides.sh` | — | keep | 11b1 | the outputs gate |
| `scripts/lib.sh` | `qa-executor` | keep | 11b1 | deferred arm |'

# build_base <dir> — a tree mirroring the base state (nothing removed yet).
build_base() {
  local d="$1"
  mkdir -p "$d/agents" "$d/commands" "$d/scripts" "$d/skills/qa-old" "$d/docs"
  printf 'agent\n' > "$d/agents/qa-x.md"
  printf 'command\n' > "$d/commands/qa-x.md"
  printf 'run\n' > "$d/scripts/verify-run.sh"
  printf 'skill\n' > "$d/skills/qa-old/SKILL.md"
  printf 'see qa-executor for runs\n' > "$d/docs/guide.md"
  printf 'map qa-strategist -> x\n' > "$d/scripts/notify.sh"
  printf 'case qa-executor) ;;\ncase qa-strategist) ;;\n' > "$d/scripts/lib.sh"
  printf 'gate\n' > "$d/scripts/verify-provides.sh"
  write_manifest "$d/m.md" auto "$BASE_ROWS"
}
apply_11b1() { rm -f "$1/agents/qa-x.md" "$1/commands/qa-x.md"; }
apply_11b2() { rm -f "$1/scripts/verify-run.sh"; }
apply_12() {
  rm -rf "$1/skills/qa-old"
  printf 'see the new agent for runs\n' > "$1/docs/guide.md"
  printf 'map other -> x\n' > "$1/scripts/notify.sh"
  printf 'case qa-executor) ;;\n' > "$1/scripts/lib.sh"
}
n_root=0
newroot() { n_root=$((n_root + 1)); R="$TMP/r$n_root"; mkdir -p "$R"; build_base "$R"; }

# ---- usage -----------------------------------------------------------------------------------------
echo "== usage"
newroot
run "$R" --manifest "$R/m.md" --bogus;            expect_rc "unknown argument" 2; expect_err "unknown argument" "--bogus"
run "$R" --manifest "$R/m.md" --expect;           expect_rc "--expect with no value" 2
run "$TMP/no-such-dir" --manifest "$R/m.md";      expect_rc "--root not a directory" 2; expect_err "--root not a directory" "no-such-dir"
run "$R" --manifest "$R/absent.md";               expect_rc "missing manifest" 2; expect_err "missing manifest" "absent.md"
run "$R";                                         expect_rc "missing manifest at the default path" 2; expect_err "missing manifest at the default path" "loomwright/docs/qa-removal-manifest.md"
run "$R" --manifest "$R/m.md" --help;             expect_rc "--help" 0

# ---- AC1: base state, report-only --------------------------------------------------------------------
echo "== AC1"
L='no `--expect` on a base-state fixture ⇒ exit 0, every delete/re-point row `pending`'
newroot
run "$R" --manifest "$R/m.md"
expect_rc "$L" 0
expect_line "$L" 'pending delete 11b1 agents/qa-x.md'
expect_line "$L" 'pending delete 11b1 commands/qa-x.md'
expect_line "$L" 'pending delete 11b2 scripts/verify-run.sh'
expect_line "$L" 'pending delete 12 skills/qa-old/'
expect_line "$L" 'pending re-point 12 docs/guide.md :: qa-executor'
expect_line "$L" 'pending re-point 11b2 scripts/notify.sh :: qa-strategist'
expect_line "$L" 'pending re-point 12 scripts/lib.sh :: qa-strategist'
expect_line "$L" 'ok keep 11b1 scripts/verify-provides.sh'
expect_line "$L" 'ok keep 11b1 scripts/lib.sh :: qa-executor'
expect_line "$L" 'summary: 9 rows, expect none: 0 MISMATCH, 7 pending, 0 done, 2 ok'
if [ "$(grep -c '' "$OUT")" = 10 ]; then ok "$L — one line per row plus the summary"; else no "$L — want 10 output lines, got $(grep -c '' "$OUT")"; fi
if [ -s "$ERR" ]; then no "$L — report-only mode wrote to stderr: $(head -2 "$ERR")"; else ok "$L — nothing on stderr"; fi
# Report-only never fails, even when a keep row is broken.
rm -f "$R/scripts/verify-provides.sh"
run "$R" --manifest "$R/m.md"
expect_rc "report-only mode with a missing keep path still exits 0" 0
expect_line "report-only mode with a missing keep path" 'pending keep 11b1 scripts/verify-provides.sh'

L='default manifest path under `--root`'
newroot
mkdir -p "$R/loomwright/docs"; mv "$R/m.md" "$R/loomwright/docs/qa-removal-manifest.md"
run "$R"
expect_rc "$L" 0
expect_line "$L" 'pending delete 11b1 agents/qa-x.md'

# ---- AC2: delete rows ------------------------------------------------------------------------------
echo "== AC2"
L='delete row present at `--expect 11b1` ⇒ exit 1 naming the path'
newroot
rm -f "$R/commands/qa-x.md"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 1
expect_line "$L" 'MISMATCH delete 11b1 agents/qa-x.md'
expect_err "$L" 'agents/qa-x.md'
expect_line "$L" 'done delete 11b1 commands/qa-x.md'
expect_line "$L" 'pending delete 11b2 scripts/verify-run.sh'
expect_line "$L" 'pending re-point 11b2 scripts/notify.sh :: qa-strategist'

L='control: every 11b1 row satisfied at `--expect 11b1` ⇒ exit 0'
newroot; apply_11b1 "$R"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 0
expect_line "$L" 'summary: 9 rows, expect 11b1: 0 MISMATCH, 5 pending, 2 done, 2 ok'

L='a dangling symlink at a delete path still exists'
newroot; apply_11b1 "$R"; ln -s "$R/nowhere" "$R/agents/qa-x.md"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 1
expect_line "$L" 'MISMATCH delete 11b1 agents/qa-x.md'

# ---- AC3: keep rows --------------------------------------------------------------------------------
echo "== AC3"
L='keep path missing at `--expect 11b1` ⇒ exit 1 naming the path'
newroot; apply_11b1 "$R"; rm -f "$R/scripts/verify-provides.sh"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 1
expect_line "$L" 'MISMATCH keep 11b1 scripts/verify-provides.sh'
expect_err "$L" 'scripts/verify-provides.sh'

L='keep file that lost its kept reference at `--expect 11b1` ⇒ exit 1 naming file + reference'
newroot; apply_11b1 "$R"; printf 'case qa-strategist) ;;\n' > "$R/scripts/lib.sh"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 1
expect_line "$L" 'MISMATCH keep 11b1 scripts/lib.sh :: qa-executor'
expect_err "$L" 'scripts/lib.sh :: qa-executor'

# ---- AC4: re-point rows ----------------------------------------------------------------------------
echo "== AC4"
L='re-point file still names `qa-executor` at `--expect 12` ⇒ exit 1 naming file + reference'
newroot; apply_11b1 "$R"; apply_11b2 "$R"; apply_12 "$R"; printf 'see qa-executor still\n' > "$R/docs/guide.md"
run "$R" --manifest "$R/m.md" --expect 12
expect_rc "$L" 1
expect_line "$L" 'MISMATCH re-point 12 docs/guide.md :: qa-executor'
expect_err "$L" 'docs/guide.md :: qa-executor'
expect_line "$L" 'done re-point 11b2 scripts/notify.sh :: qa-strategist'

L='control: every row satisfied at `--expect 12` ⇒ exit 0'
newroot; apply_11b1 "$R"; apply_11b2 "$R"; apply_12 "$R"
run "$R" --manifest "$R/m.md" --expect 12
expect_rc "$L" 0
expect_line "$L" 'summary: 9 rows, expect 12: 0 MISMATCH, 0 pending, 7 done, 2 ok'
expect_line "$L" 'ok keep 11b1 scripts/lib.sh :: qa-executor'

L='re-point file missing at `--expect 12` ⇒ MISMATCH, never done'
newroot; apply_11b1 "$R"; apply_11b2 "$R"; apply_12 "$R"; rm -f "$R/docs/guide.md"
run "$R" --manifest "$R/m.md" --expect 12
expect_rc "$L" 1
expect_line "$L" 'MISMATCH re-point 12 docs/guide.md :: qa-executor'

L='re-point file unreadable at `--expect 12` ⇒ MISMATCH, never done'
newroot; apply_11b1 "$R"; apply_11b2 "$R"; apply_12 "$R"; chmod 000 "$R/docs/guide.md"
if [ -r "$R/docs/guide.md" ]; then
  ok "$L — skipped: chmod 000 does not make a file unreadable for this user (root)"
else
  run "$R" --manifest "$R/m.md" --expect 12
  expect_rc "$L" 1
  expect_line "$L" 'MISMATCH re-point 12 docs/guide.md :: qa-executor'
fi
chmod 644 "$R/docs/guide.md"

L='re-point rows are not checked before `--expect 12`'
newroot; apply_11b1 "$R"; apply_11b2 "$R"
run "$R" --manifest "$R/m.md" --expect 11b2
expect_rc "$L" 0
expect_line "$L" 'pending re-point 11b2 scripts/notify.sh :: qa-strategist'

# ---- item ordering ---------------------------------------------------------------------------------
echo "== ordering"
L='`--expect 11b2` still checks an `11b1` delete row and does not check a `12` row'
newroot; apply_11b2 "$R"; rm -f "$R/commands/qa-x.md"
run "$R" --manifest "$R/m.md" --expect 11b2
expect_rc "$L" 1
expect_line "$L" 'MISMATCH delete 11b1 agents/qa-x.md'
expect_line "$L" 'done delete 11b2 scripts/verify-run.sh'
expect_line "$L" 'pending delete 12 skills/qa-old/'
expect_no_line "$L" 'MISMATCH delete 12 skills/qa-old/'
L='`--expect 11b1` does not check an `11b2` row'
newroot; apply_11b1 "$R"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 0
expect_line "$L" 'pending delete 11b2 scripts/verify-run.sh'

# ---- AC5: refusals ---------------------------------------------------------------------------------
echo "== AC5"
# refuse_leg <label> <row-count|auto> <rows> <stderr text that names the row> [extra checker args...]
refuse_leg() {
  local label="$1" n="$2" rows="$3" want="$4"; shift 4
  newroot
  write_manifest "$R/m.md" "$n" "$rows"
  run "$R" --manifest "$R/m.md" "$@"
  expect_rc "$label" 2
  expect_err "$label" "$want"
  expect_no_rows "$label"
}
refuse_leg 'unknown action ⇒ exit 2' auto "$BASE_ROWS
| \`agents/extra.md\` | — | remove | 11b1 | typo'd action |" 'line 18: unknown action `remove`'
refuse_leg 'unknown item (not `11b1`/`11b2`/`12`) ⇒ exit 2' auto "$BASE_ROWS
| \`agents/extra.md\` | — | delete | 13 | wrong item |" 'line 18: unknown item `13`'
refuse_leg 'header `Row count:` ≠ parsed rows ⇒ exit 2' 8 "$BASE_ROWS" 'header `Row count: 8` but the table has 9 data rows'
refuse_leg 'header `Row count:` ≠ parsed rows ⇒ exit 2 (count too high)' 10 "$BASE_ROWS" 'the table has 9 data rows'
refuse_leg 'duplicate (path, reference) row ⇒ exit 2' auto "$BASE_ROWS
| \`docs/guide.md\` | \`qa-executor\` | re-point | 11b2 | same row again |" 'line 18: duplicate (path, reference) row — same as line 13: docs/guide.md :: qa-executor'
refuse_leg 'duplicate (path, reference) row ⇒ exit 2 (a trailing / names the same path)' auto "$BASE_ROWS
| \`skills/qa-old\` | — | delete | 12 | same dir |" 'line 18: duplicate (path, reference) row — same as line 12: skills/qa-old'
refuse_leg 'a `keep` and a `re-point` row on the same (path, reference) ⇒ exit 2' auto "$BASE_ROWS
| \`scripts/lib.sh\` | \`qa-executor\` | re-point | 12 | contradicts the keep row |" 'line 18: conflicting actions keep/re-point on the same (path, reference) as line 17: scripts/lib.sh :: qa-executor'
refuse_leg 'a `delete` and a `keep` row on the same path ⇒ exit 2' auto "$BASE_ROWS
| \`agents/qa-x.md\` | — | keep | 11b1 | contradicts the delete row |" 'conflicting actions delete/keep on the same (path, reference) as line 9: agents/qa-x.md'

L='unknown `--expect` value ⇒ exit 2'
newroot
run "$R" --manifest "$R/m.md" --expect 11b3
expect_rc "$L" 2; expect_err "$L" "unknown --expect value '11b3'"; expect_no_rows "$L"
run "$R" --manifest "$R/m.md" --expect ''
expect_rc "$L (empty value)" 2

refuse_leg 'a delete row with a reference ⇒ exit 2' auto '| `agents/qa-x.md` | `qa-executor` | delete | 11b1 | wrong shape |' 'line 9: a `delete` row removes the whole path'
refuse_leg 'a re-point row without a reference ⇒ exit 2' auto '| `docs/guide.md` | — | re-point | 12 | nothing to check |' 'line 9: a `re-point` row needs a reference to check: docs/guide.md'
refuse_leg 'an empty reason ⇒ exit 2' auto '| `agents/qa-x.md` | — | delete | 11b1 |  |' 'line 9: empty reason: agents/qa-x.md'
refuse_leg 'a wrong cell count ⇒ exit 2' auto '| `agents/qa-x.md` | — | delete | 11b1 |' 'line 9: want 5 cells'
refuse_leg 'a row not ending in | ⇒ exit 2' auto '| `agents/qa-x.md` | — | delete | 11b1 | no end' 'line 9: a row must start and end with `|`'
refuse_leg 'a path with a leading ./ ⇒ exit 2' auto '| `./agents/qa-x.md` | — | delete | 11b1 | r |' 'line 9: path must be repo-relative'
refuse_leg 'a path with a .. part ⇒ exit 2' auto '| `agents/../../etc/passwd` | — | delete | 11b1 | r |' 'line 9: path must be repo-relative'
refuse_leg 'a path with a . part ⇒ exit 2' auto '| `agents/./qa-x.md` | — | delete | 11b1 | r |' 'line 9: path must be repo-relative'
refuse_leg 'a path with // ⇒ exit 2' auto '| `agents//qa-x.md` | — | delete | 11b1 | r |' 'line 9: path must be repo-relative'
refuse_leg 'the root itself as a path ⇒ exit 2' auto '| `.` | — | delete | 11b1 | r |' 'line 9: path must be repo-relative'
refuse_leg 'an absolute path ⇒ exit 2' auto '| `/etc/passwd` | — | delete | 11b1 | r |' 'line 9: path must be repo-relative'
refuse_leg 'an unbackticked path ⇒ exit 2' auto '| agents/qa-x.md | — | delete | 11b1 | r |' 'line 9: path must be one backticked'
refuse_leg 'an unbackticked reference ⇒ exit 2' auto '| `docs/guide.md` | qa-executor | re-point | 12 | r |' 'line 9: reference must be a backticked string'
refuse_leg 'zero data rows ⇒ exit 2' 0 '' 'the `## Rows` table has no data rows'

L='a table row after a blank line ⇒ exit 2 (never skipped)'
newroot
write_manifest "$R/m.md" 2 '| `agents/qa-x.md` | — | delete | 11b1 | r |

| `commands/qa-x.md` | — | delete | 11b1 | r |'
run "$R" --manifest "$R/m.md"
expect_rc "$L" 2; expect_err "$L" 'line 11: a table row after the `## Rows` table ended'; expect_no_rows "$L"

# raw_refuse_leg <label> <manifest text> <stderr text>
raw_refuse_leg() {
  newroot
  printf '%s\n' "$2" > "$R/m.md"
  run "$R" --manifest "$R/m.md"
  expect_rc "$1" 2; expect_err "$1" "$3"; expect_no_rows "$1"
}
ROW1='| `agents/qa-x.md` | — | delete | 11b1 | r |'
HDR='| path | reference | action | item | reason |'
raw_refuse_leg 'no `Row count:` line ⇒ exit 2' "## Rows

$HDR
|---|---|---|---|---|
$ROW1" 'no column-0 `Row count: <N>` line'
raw_refuse_leg 'a `Row count:` line only inside a code fence ⇒ exit 2' '```
Row count: 1
```

## Rows

'"$HDR"'
|---|---|---|---|---|
'"$ROW1" 'no column-0 `Row count: <N>` line'
raw_refuse_leg 'two `Row count:` lines ⇒ exit 2' "Row count: 1
Row count: 1

## Rows

$HDR
|---|---|---|---|---|
$ROW1" '2 `Row count:` lines'
raw_refuse_leg 'a malformed `Row count:` line ⇒ exit 2' "Row count: one

## Rows

$HDR
|---|---|---|---|---|
$ROW1" 'line 1: malformed row-count line'
raw_refuse_leg 'a `Row count:` line after the table ⇒ exit 2' "## Rows

$HDR
|---|---|---|---|---|
$ROW1

Row count: 1" 'must come before the table'
raw_refuse_leg 'no `## Rows` heading ⇒ exit 2' "Row count: 1

## Entries

$HDR
|---|---|---|---|---|
$ROW1" 'no `## Rows` heading'
raw_refuse_leg 'a wrong table header ⇒ exit 2' "Row count: 1

## Rows

| path | ref | action | item | reason |
|---|---|---|---|---|
$ROW1" 'line 5: the `## Rows` table header must be exactly'
raw_refuse_leg 'a missing separator line ⇒ exit 2' "Row count: 1

## Rows

$HDR
$ROW1" 'line 6: the line after the table header must be a `|---|` separator'
raw_refuse_leg 'a second `## Rows` heading ⇒ exit 2' "Row count: 1

## Rows

$HDR
|---|---|---|---|---|
$ROW1

## Rows
" 'line 9: a second `## Rows` heading'

# ---- cells -----------------------------------------------------------------------------------------
echo "== cells"
L='an escaped \| in a reference reads as a literal |'
newroot
printf 'run a|b now\n' > "$R/docs/pipe.md"
write_manifest "$R/m.md" auto '| `docs/pipe.md` | `a\|b` | re-point | 12 | piped |'
run "$R" --manifest "$R/m.md" --expect 12
expect_rc "$L" 1
expect_line "$L" 'MISMATCH re-point 12 docs/pipe.md :: a|b'

L='a reference starting with - is matched as text, not read as an option'
newroot
printf 'flag --qa-run here\n' > "$R/docs/flag.md"
write_manifest "$R/m.md" auto '| `docs/flag.md` | `--qa-run` | keep | 11b1 | flag |'
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 0
expect_line "$L" 'ok keep 11b1 docs/flag.md :: --qa-run'
printf 'flag gone\n' > "$R/docs/flag.md"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L (reference gone)" 1

L='a double-backtick reference may carry a backtick'
newroot
printf 'call `qa-run` here\n' > "$R/docs/tick.md"
write_manifest "$R/m.md" auto '| `docs/tick.md` | `` `qa-run` `` | keep | 11b1 | tick |'
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 0
expect_line "$L" 'ok keep 11b1 docs/tick.md :: `qa-run`'

L='a dot-directory path (e.g. `.github/…`) is a valid repo-relative path'
newroot
mkdir -p "$R/.github/workflows"; printf 'steps: qa-cache\n' > "$R/.github/workflows/ci.yml"
write_manifest "$R/m.md" auto '| `.github/workflows/ci.yml` | `qa-cache` | re-point | 11b2 | cache step |'
run "$R" --manifest "$R/m.md"
expect_rc "$L" 0
expect_line "$L" 'pending re-point 11b2 .github/workflows/ci.yml :: qa-cache'

L='a directory row with a reference is searched recursively'
newroot
mkdir -p "$R/docs/evidence/old"; printf 'mentions qa-executor\n' > "$R/docs/evidence/old/run.md"
write_manifest "$R/m.md" auto '| `docs/evidence/` | `qa-executor` | keep | 11b1 | history |'
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L" 0
expect_line "$L" 'ok keep 11b1 docs/evidence/ :: qa-executor'
printf 'nothing\n' > "$R/docs/evidence/old/run.md"
run "$R" --manifest "$R/m.md" --expect 11b1
expect_rc "$L (reference gone from every file)" 1

L='a symlinked directory row is followed'
newroot
mkdir -p "$R/real"; printf 'mentions qa-executor\n' > "$R/real/run.md"; ln -s "$R/real" "$R/docs/linked"
write_manifest "$R/m.md" auto '| `docs/linked` | `qa-executor` | re-point | 12 | linked |'
run "$R" --manifest "$R/m.md" --expect 12
expect_rc "$L" 1
expect_line "$L" 'MISMATCH re-point 12 docs/linked :: qa-executor'

# ---- the committed manifest (the real tree, read only) ---------------------------------------------
# Only exit status and the absence of a refusal are pinned here: row statuses change as 11b1, 11b2 and
# 12 land, so the `pending` wording is pinned on the base-state fixture (AC1) instead.
echo "== real-repo"
REPO="$(cd "$HERE/../.." && pwd)"
REAL="$REPO/loomwright/docs/qa-removal-manifest.md"
L='real-repo leg (no `--expect`, exit 0, no refusal)'
RC=0; bash "$SCRIPT" --root "$REPO" >"$OUT" 2>"$ERR" || RC=$?   # default manifest path, on purpose
expect_rc "$L" 0
if contains "$ERR" 'REFUSED'; then no "$L — the committed manifest was refused: $(head -3 "$ERR" | tr '\n' ' ')"; else ok "$L — no refusal"; fi
if grep -q '^summary: [0-9][0-9]* rows, expect none: 0 MISMATCH' "$OUT"; then ok "$L — summary line"; else no "$L — no summary line in: $(tail -2 "$OUT" | tr '\n' '|')"; fi

# The enforcing leg: every row up to the last landed item must hold on the real tree, so a keep row
# (e.g. the `qa-executor:*)` arm, `verify-provides.sh`) that disappears fails CI here. Raise LANDED in
# the same change that lands the next item.
LANDED=11b2
L="real-repo leg (\`--expect $LANDED\`, exit 0)"
RC=0; bash "$SCRIPT" --root "$REPO" --expect "$LANDED" >"$OUT" 2>"$ERR" || RC=$?
if [ "$RC" = 0 ]; then
  ok "$L"
else
  no "$L — rc=$RC: $(grep -E '^(MISMATCH|pending)' "$OUT" | head -5 | tr '\n' '|') $(head -3 "$ERR" | tr '\n' ' ')"
fi
if grep -q "^summary: [0-9][0-9]* rows, expect $LANDED: 0 MISMATCH" "$OUT"; then ok "$L — summary line"; else no "$L — no summary line in: $(tail -2 "$OUT" | tr '\n' '|')"; fi

echo "== AC6 scope rows"
L='AC6 scope rows: the real manifest has a row for each Scope-named path'
# has_row <path> [<reference cell>] — a data row of the committed manifest starts with that path cell
# (and that reference cell, written exactly as in the table).
has_row() {
  local want="| \`$1\` |"
  if [ "$#" -ge 2 ]; then want="$want $2 |"; fi
  awk -v w="$want" 'index($0, w) == 1 { f = 1 } END { exit !f }' "$REAL"
}
need_row() { if has_row "$@"; then ok "$L — $1${2:+ :: $2}"; else no "$L — no row for $1${2:+ :: $2}"; fi; }
if [ ! -f "$REAL" ]; then
  no "$L — the committed manifest is missing: $REAL"
else
  need_row 'loomwright/capabilities.json'
  need_row '.claude-plugin/marketplace.json' '`qa-executor`'                 # keywords
  need_row '.claude-plugin/marketplace.json' '`red-teaming, QA,`'            # description (counts)
  need_row 'loomwright/.claude-plugin/plugin.json' '`qa-executor`'           # keywords
  need_row 'loomwright/.claude-plugin/plugin.json' '`red-teaming, QA,`'      # description (counts)
  need_row '.github/workflows/ci.yml' '`read-playwright-pin.sh`'             # the Playwright pin step
  need_row '.github/workflows/ci.yml' '`verify-walkthrough`'                 # the cache step
  need_row 'loomwright/hooks/hooks.json' '`qa-executor`'                     # the two matchers
  need_row 'loomwright/hooks/hooks.json' '`qa-strategist`'
  need_row 'loomwright/hooks/hooks.json' '`validate-qa-result.py`'
  need_row 'loomwright/docs/prompt-token-budgets.json' '`qa-executor`'
  need_row 'loomwright/docs/ARCHITECTURE_CONTRACTS.md' '`qa-executor`'       # the budget mirror table
  need_row 'loomwright/docs/ARCHITECTURE_CONTRACTS.md' '`` `verify` ``'
  need_row 'CLAUDE.md' '`QA Executor`'                                       # the agent-roles table
  need_row 'CLAUDE.md' '`QA Strategist`'
  # The tracked agent-memory dir: exactly its tracked files, each a delete row of 11b1. Matched by the
  # dir's name, so this test names no harness config dir.
  MEM='agent-memory/loomwright-loomwright-qa-executor/'
  n_mem="$(awk -v m="$MEM" 'index($0, "| `") == 1 && index($0, m) { n++ } END { print n + 0 }' "$REAL")"
  n_mem_del="$(awk -v m="$MEM" 'index($0, "| `") == 1 && index($0, m) && index($0, "` | — | delete | 11b1 | ") { n++ } END { print n + 0 }' "$REAL")"
  if [ "$n_mem" = 9 ]; then ok "$L — 9 rows under $MEM"; else no "$L — want 9 rows under $MEM, got $n_mem"; fi
  if [ "$n_mem_del" = 9 ]; then ok "$L — each is a whole-path 11b1 delete row"; else no "$L — want 9 delete/11b1 rows under $MEM, got $n_mem_del"; fi
fi

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
