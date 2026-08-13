#!/usr/bin/env bash
# test-write-agent-memory.sh — hermetic offline self-tests for write-agent-memory.sh, the SIXTH
# sole writer and the OWNER of each agent-memory store's MEMORY.md index. Mirrors the
# test-add-orientation.sh harness convention (pass/fail counters, ok()/no(), a RESULT tail, exit 1
# on any failure). Auto-registered by ci.yml's test-*.sh glob. No network, no Docker.
#
# FIXTURE-ONLY, AND THAT IS LOAD-BEARING — NOT A CONVENIENCE.
# Every store this suite touches is a seeded fixture under a `mktemp -d` sandbox. It NEVER reads,
# writes or asserts on the repo's live `.claude/agent-memory/` stores. The reason is specific: all
# three live stores are already HEALTHY (N files / N-1 pointers — MEMORY.md does not index itself),
# so an assertion that merely OBSERVES a live store passes identically against a writer that does
# nothing at all. That is the vacuous-guard class this whole item exists to close, so the index
# assertions below are made against a store deliberately seeded INTO the rotted shape (4 files,
# 1 pointer) and are proven to go RED when the rebuild is removed.
#
# MUTATION CONTROLS ARE PART OF THE SUITE, NOT A ONE-OFF MANUAL STEP.
# Three assertions here are only meaningful if the thing they name is load-bearing, so the suite
# BUILDS the mutant itself, proves the mutation was non-vacuous (the file really changed), and
# asserts the mutant misbehaves where the real writer does not:
#   · (M1) the INDEX REBUILD call removed        ⇒ the seeded rot survives          (AC7 goes RED)
#   · (M2) the VALIDATOR CALL removed            ⇒ a seeded duplicate is written    (AC1 goes RED)
#   · (M3) the LOAD GUARD replaced with `|| true`⇒ no named refusal; a sentinel-less
#          validator is used unchecked and the write lands                          (AC2 goes RED)
#   · (M4) `--store` pointed back at MEMORY.md   ⇒ a byte-for-byte repost of a stored
#          entry's body under a new slug is WRITTEN                                 ((i) goes RED)
#   · (M5) the index lock ACQUISITION stripped   ⇒ the writer rebuilds MEMORY.md straight
#          through a lock another writer holds                                      ((j2) goes RED)
# Each mutant is `bash -n`-checked before use: a mutant that does not parse would "fail" for the
# wrong reason and read as proof when it is noise.
#
# Cases:
#   (a)  happy path: entry written, frontmatter reads back, index rebuilt and names the entry
#   (a2) the writer OWNS MEMORY.md: the store's H1 title line survives a rebuild, the body does not
#   (b)  AC7 — a store seeded INTO the rotted shape is repaired by one write; N files / N-1 pointers
#   (b2) AC7 mutation control M1 — with the rebuild removed, the same fixture stays rotted
#   (c)  AC8 — a proposal file under .supervisor/agent-memory-proposals/ round-trips:
#        validated write → entry in the store → named in the rebuilt index
#   (c2) an incomplete proposal is REFUSED (could-not-examine class), nothing written
#   (d)  AC1 — each of the five checks refuses, names its reason, and leaves the store BYTE-IDENTICAL
#   (d2) AC1 mutation control M2 — with the validator call removed, a seeded duplicate is written
#   (e)  AC2 — absent / unparseable / truncated-at-a-function-boundary / sentinel-stripped validator:
#        all four refuse with exit 2, a NAMED greppable reason, and a byte-identical store
#   (e2) AC2 mutation control M3 — the guard replaced with `|| true`
#   (i)  the comparison corpus is the store's ENTRY FILES, not MEMORY.md: a realistically-sized
#        entry whose BODY duplicates a stored entry under a DIFFERENT slug is REFUSED, while a
#        genuinely different entry of the same size is still ACCEPTED (the false-refusal control)
#   (i2) (i)'s mutation control M4 — `--store` pointed back at the index; the repost is written
#   (f)  AC10c — a git WORKTREE cwd is refused with exit 3, an explicit --repo worktree too, and the
#        NON-GIT-REPO fallback stays PERMISSIVE (pwd), never write-lessons.sh's hard exit 2
#   (j)  CONCURRENCY — the MEMORY.md rebuild is serialized by a lock directory:
#        (j1) N overlapping writers all end up named in the index (no lost pointer, no deadlock,
#             no leaked lock); (j2) a lock the writer cannot acquire is a NAMED refusal with the
#             entry rolled back, never a silently skipped rebuild; (j3) mutation control M5
#   (g)  the confirm-only gate: non-TTY without --confirm is a dry-run that writes NOTHING
#   (h)  no `.write-agent-memory.*` temp residue after a successful write (atomicity)

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write-agent-memory.sh"
VALIDATOR="$SCRIPT_DIR/validate-entry.sh"

pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
no() { echo "FAIL: $1"; fail=$((fail+1)); }

# A SETUP failure is not a behavioural failure — abort loudly rather than let a mis-built fixture
# masquerade as a defect in the writer.
setup_fail() { echo "SETUP FAILURE: $1" >&2; echo "ABORTED: the assertions below would be meaningless." >&2; exit 2; }

ROOT="$(mktemp -d 2>/dev/null)"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || setup_fail "mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX" || setup_fail "mktemp -d under $ROOT failed"; }

echo "== 0. scripts under test exist =="
[ -f "$WRITER" ] && ok "write-agent-memory.sh present" || no "write-agent-memory.sh missing at $WRITER"
[ -f "$VALIDATOR" ] && ok "validate-entry.sh present (the shared validator this writer sources)" || no "validate-entry.sh missing at $VALIDATOR"
if [ ! -f "$WRITER" ] || [ ! -f "$VALIDATOR" ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi

# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------
# A real git repo, so head_sha resolves and the worktree cases have something to branch from.
new_repo() {
  local r; r="$(mktmp)"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && git config core.excludesFile /dev/null \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1 \
    || setup_fail "could not build a git fixture repo at $r"
  printf '%s' "$r"
}

AGENT="loomwright-loomwright-code-reviewer"

# store_sum <dir> — a content fingerprint of every file under a store dir, used for the
# BYTE-UNCHANGED assertions. Includes the relative path so a rename is visible too. `cksum` reads
# from stdin so no filename ever reaches the checksum text.
store_sum() {
  ( cd "$1" 2>/dev/null || return 0
    find . -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s ' "$f"; cksum < "$f" 2>/dev/null
    done )
}

# index_pointers <index-file> — how many `- [title](file.md)` pointers the index carries.
index_pointers() {
  local n
  n="$(grep -cE '^- \[[^]]*\]\([^)]*\.md\)' "$1" 2>/dev/null || true)"
  [ -n "$n" ] || n=0
  printf '%s' "$n"
}

# store_files <agent-dir> — how many *.md files the store holds, MEMORY.md included.
store_files() { ls "$1"/*.md 2>/dev/null | wc -l | tr -d '[:space:]'; }

# run <repo> <store-root> <args...> — sets OUT and RC. Always non-TTY (stdin from /dev/null) so the
# confirm gate's automated path is what is exercised unless a case passes --confirm itself.
run() {
  local repo="$1" store="$2"; shift 2
  OUT="$(bash "$WRITER" "$@" --repo "$repo" --store "$store" < /dev/null 2>&1)"; RC=$?
}

# run_with <writer> <repo> <store-root> <args...> — the same, for a MUTANT writer. The mutant lives
# in a scratch dir, so the validator has to be pointed at explicitly.
run_with() {
  local w="$1" repo="$2" store="$3"; shift 3
  OUT="$(WRITE_AGENT_MEMORY_VALIDATOR="$VALIDATOR" bash "$w" "$@" --repo "$repo" --store "$store" < /dev/null 2>&1)"; RC=$?
}

# mkbody <path> [body-text] — NOTE `${2-...}`, NOT `${2:-...}`. The colon form also substitutes on
# an EMPTY second argument, which silently padded every "the body is empty" fixture below with the
# default paragraph — and that quietly dropped the duplicate case's similarity score from 100 to 60,
# under the check's own threshold, so the duplicate went undetected and the case passed as a WRITE.
# The distinction is load-bearing: several cases need the entry text to be the summary and nothing
# else, so that the score they assert on is the one they reason about.
mkbody() { printf '%s\n' "${2-A short body paragraph for the fixture entry.}" > "$1"; printf '%s' "$1"; }

# ---------------------------------------------------------------------------
# (a) happy path
# ---------------------------------------------------------------------------
echo "== (a) happy path: entry written, frontmatter reads back, index rebuilt =="
RA="$(new_repo)"; SA="$RA/.claude/agent-memory"
BA="$(mkbody "$RA/body-a.md")"
run "$RA" "$SA" "$AGENT" first_entry "the first fixture entry about gate behaviour" "$BA" --source "PR #140" --title "First entry" --confirm
[ "$RC" -eq 0 ] && ok "(a) a valid write exits 0" || no "(a) a valid write exited $RC — $OUT"
[ -f "$SA/$AGENT/first_entry.md" ] && ok "(a) the entry file exists in the store" || no "(a) the entry file was not created"
grep -q '^name: first_entry$' "$SA/$AGENT/first_entry.md" 2>/dev/null && ok "(a) the entry's frontmatter 'name:' reads back" || no "(a) the entry's frontmatter is missing/unparseable"
grep -q '^description: the first fixture entry about gate behaviour$' "$SA/$AGENT/first_entry.md" 2>/dev/null && ok "(a) the summary lands in 'description:' (the field the index quotes)" || no "(a) the summary did not reach the frontmatter"
[ -f "$SA/$AGENT/MEMORY.md" ] && ok "(a) MEMORY.md was created by the write" || no "(a) MEMORY.md was not created"
grep -qF '(first_entry.md)' "$SA/$AGENT/MEMORY.md" 2>/dev/null && ok "(a) the rebuilt index NAMES the new entry" || no "(a) the rebuilt index does not name the new entry"
grep -qF 'First entry' "$SA/$AGENT/MEMORY.md" 2>/dev/null && ok "(a) the index pointer carries the entry's --title" || no "(a) the index pointer lost the title"

echo "== (a2) the writer OWNS MEMORY.md: the H1 title survives, the body is re-derived =="
printf '# Code Reviewer Memory — loomwright\n\n- [stale hand-written pointer](gone.md) — a file that no longer exists\n' > "$SA/$AGENT/MEMORY.md"
BA2="$(mkbody "$RA/body-a2.md")"
run "$RA" "$SA" "$AGENT" second_entry "a second fixture entry recorded after PR #141 landed" "$BA2" --source "PR #141" --confirm
[ "$RC" -eq 0 ] && ok "(a2) the second write exits 0" || no "(a2) the second write exited $RC — $OUT"
[ "$(head -n 1 "$SA/$AGENT/MEMORY.md")" = "# Code Reviewer Memory — loomwright" ] && ok "(a2) the store's H1 title line SURVIVED the rebuild" || no "(a2) the rebuild clobbered the store's H1 title (got: $(head -n 1 "$SA/$AGENT/MEMORY.md"))"
grep -qF '(gone.md)' "$SA/$AGENT/MEMORY.md" 2>/dev/null && no "(a2) a pointer to a NON-EXISTENT file survived the rebuild — the index is being patched, not re-derived" || ok "(a2) the pointer to a non-existent file is GONE — the index is re-derived from the files on disk, never patched"
[ "$(index_pointers "$SA/$AGENT/MEMORY.md")" = "2" ] && ok "(a2) the rebuilt index carries exactly the two real entries" || no "(a2) the rebuilt index carries $(index_pointers "$SA/$AGENT/MEMORY.md") pointers, expected 2"

# ---------------------------------------------------------------------------
# (b) AC7 — the seeded ROT fixture. This is the assertion the whole item turns on.
# ---------------------------------------------------------------------------
echo "== (b) AC7: a store seeded INTO the rotted shape is repaired by one write =="

# seed_rotted <store-root> — 4 entry files, an index naming ONE of them. Echoes the agent dir.
seed_rotted() {
  local sr="$1" d="$1/$AGENT" i
  mkdir -p "$d" || setup_fail "could not create the seeded store dir $d"
  for i in alpha beta gamma delta; do
    printf -- '---\nname: %s\ntitle: Seeded %s\ndescription: seeded entry %s, present on disk\nmetadata:\n  type: project\n---\nbody of %s\n' \
      "$i" "$i" "$i" "$i" > "$d/$i.md" || setup_fail "could not seed $d/$i.md"
  done
  printf '# Seeded Store Memory\n\n- [Seeded alpha](alpha.md) — seeded entry alpha, present on disk\n' > "$d/MEMORY.md" \
    || setup_fail "could not seed $d/MEMORY.md"
  printf '%s' "$d"
}

RB="$(new_repo)"; SB="$RB/.claude/agent-memory"
DB="$(seed_rotted "$SB")"
# PRECONDITION, asserted — without it this whole group could pass against an already-healthy store,
# which is exactly the failure mode PRE-FLIGHT CORRECTION 1 names.
n_files_pre="$(store_files "$DB")"; n_ptrs_pre="$(index_pointers "$DB/MEMORY.md")"
if [ "$n_files_pre" = "5" ] && [ "$n_ptrs_pre" = "1" ]; then
  ok "(b) PRECONDITION: the fixture is genuinely ROTTED — 5 files, 1 index pointer (3 entries invisible to the agent that owns them)"
else
  no "(b) the fixture is not in the rotted shape (files=$n_files_pre, pointers=$n_ptrs_pre) — every assertion below would be vacuous"
fi
BB="$(mkbody "$RB/body-b.md")"
run "$RB" "$SB" "$AGENT" epsilon "a fresh entry written after the postmortem in PR #142" "$BB" --source "PR #142" --confirm
[ "$RC" -eq 0 ] && ok "(b) the write into the rotted store exits 0" || no "(b) the write into the rotted store exited $RC — $OUT"
n_files_post="$(store_files "$DB")"; n_ptrs_post="$(index_pointers "$DB/MEMORY.md")"
[ "$n_files_post" = "6" ] && ok "(b) the store now holds 6 .md files (4 seeded + the new one + MEMORY.md)" || no "(b) the store holds $n_files_post .md files, expected 6"
[ "$n_ptrs_post" = "5" ] && ok "(b) the index now holds 5 pointers — the N files / N-1 pointers rule holds (MEMORY.md does not index itself)" || no "(b) the index holds $n_ptrs_post pointers, expected 5 (N-1)"
b_missing=""
for i in alpha beta gamma delta epsilon; do
  grep -qF "($i.md)" "$DB/MEMORY.md" 2>/dev/null || b_missing="$b_missing $i"
done
[ -z "$b_missing" ] && ok "(b) EVERY entry file on disk is now named by the index, including the three that were invisible before the write" || no "(b) still unindexed after the write:$b_missing"
[ "$(head -n 1 "$DB/MEMORY.md")" = "# Seeded Store Memory" ] && ok "(b) the seeded store's H1 title survived the repair" || no "(b) the repair clobbered the seeded H1 title"

echo "== (b2) AC7 MUTATION CONTROL M1: with the index rebuild removed, the rot SURVIVES =="
MUT_DIR="$(mktmp)"
M1="$MUT_DIR/mutant-no-rebuild.sh"
# Strip EVERY call site — any line whose first non-space token is `rebuild_memory_index ` — while
# keeping the function (its DEFINITION line is `rebuild_memory_index() {`, with `(` and no space,
# so it survives). That is the "sources it but never invokes it" shape the control must model.
# ANCHORING AT COLUMN 0 IS NOT ENOUGH, and this is not hypothetical: when undo_write gained its own
# rebuild calls (indented, inside the function), a column-0-only mutant left them live, the failed
# read-back drove undo_write, and the mutant REBUILT THE INDEX ANYWAY — self-healing into a green
# control that proved nothing. A mutation control has to track every path that can do the work.
n_call_orig="$(grep -c '^[[:space:]]*rebuild_memory_index ' "$WRITER" 2>/dev/null || true)"; [ -n "$n_call_orig" ] || n_call_orig=0
sed -e '/^[[:space:]]*rebuild_memory_index /s/.*/:/' "$WRITER" > "$M1" || setup_fail "could not build mutant M1"
n_call_mut="$(grep -c '^[[:space:]]*rebuild_memory_index ' "$M1" 2>/dev/null || true)"; [ -n "$n_call_mut" ] || n_call_mut=0
if [ "$n_call_orig" -ge 1 ] && [ "$n_call_mut" -eq 0 ]; then
  ok "(b2) the mutation is NON-VACUOUS: $n_call_orig rebuild call site(s) in the real writer, 0 in the mutant"
else
  no "(b2) the mutation changed nothing (orig=$n_call_orig, mutant=$n_call_mut) — the control below would prove nothing"
fi
bash -n "$M1" 2>/dev/null && ok "(b2) the mutant still parses (so a failure below is behavioural, not a syntax error)" || no "(b2) mutant M1 does not parse — it could not discriminate anything"
RB2="$(new_repo)"; SB2="$RB2/.claude/agent-memory"; DB2="$(seed_rotted "$SB2")"
BB2="$(mkbody "$RB2/body-b2.md")"
run_with "$M1" "$RB2" "$SB2" "$AGENT" epsilon "a fresh entry written after the postmortem in PR #142" "$BB2" --source "PR #142" --confirm
# THE assertion: the seeded rot SURVIVES the mutant. This is what makes (b) load-bearing rather
# than an observation that would hold against a writer doing nothing.
m1_ptrs="$(index_pointers "$DB2/MEMORY.md")"
[ "$m1_ptrs" = "1" ] && ok "(b2) M1 CONFIRMED: without the rebuild the seeded rot SURVIVES — still 1 index pointer where the real writer produced 5, so (b) goes RED and is load-bearing" || no "(b2) the index moved to $m1_ptrs pointers WITHOUT the rebuild call — (b) is passing for some other reason and is vacuous"
# SECOND, INDEPENDENT DEFENCE, recorded rather than assumed: the mutant does not merely produce a
# stale index, it FAILS OUTRIGHT — the read-back verify ("the rebuilt MEMORY.md does not name
# <slug>.md") notices the pointer never appeared and rolls the entry file back. So a rebuild that
# silently produced nothing cannot be shipped as a successful write either.
if [ "$RC" -ne 0 ] && [ ! -f "$DB2/epsilon.md" ]; then
  ok "(b2) and the mutant's own read-back verify caught the missing rebuild: exit $RC, entry rolled back — a silently-skipped rebuild cannot present itself as a successful write"
else
  no "(b2) the mutant reported success (rc=$RC, entry present=$([ -f "$DB2/epsilon.md" ] && echo yes || echo no)) — the read-back verify does not check that the index names the new entry"
fi

# ---------------------------------------------------------------------------
# (c) AC8 — the proposal queue round-trips.
# ---------------------------------------------------------------------------
echo "== (c) AC8: proposal → validated write → indexed entry =="
RC1="$(new_repo)"; SC="$RC1/.claude/agent-memory"
PROP_DIR="$RC1/.supervisor/agent-memory-proposals"
mkdir -p "$PROP_DIR" || setup_fail "could not create the proposal dir"
PROP="$PROP_DIR/2026-08-10-surprising-gate.md"
cat > "$PROP" <<PROPOSAL
---
agent: $AGENT
name: surprising_gate
title: Surprising gate
description: the gate refused a write that every earlier run had accepted, discovered in PR #143
source: PR #143
metadata:
  type: project
---
The body of the proposal, promoted verbatim into the store entry.
PROPOSAL
[ -f "$PROP" ] && ok "(c) the proposal fixture exists under .supervisor/agent-memory-proposals/" || no "(c) the proposal fixture was not created"
OUT="$(bash "$WRITER" --proposal "$PROP" --repo "$RC1" --store "$SC" --confirm < /dev/null 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "(c) promoting the proposal exits 0" || no "(c) promoting the proposal exited $RC — $OUT"
[ -f "$SC/$AGENT/surprising_gate.md" ] && ok "(c) the promoted entry is IN THE STORE, routed by the proposal's 'agent:' field" || no "(c) the promoted entry is not in the store"
grep -qF 'The body of the proposal, promoted verbatim' "$SC/$AGENT/surprising_gate.md" 2>/dev/null && ok "(c) the proposal's BODY was promoted, not just its frontmatter" || no "(c) the proposal body did not reach the entry"
grep -qF '(surprising_gate.md)' "$SC/$AGENT/MEMORY.md" 2>/dev/null && ok "(c) MEMORY.md NAMES the promoted entry — proposal → validated write → indexed entry closes" || no "(c) the promoted entry is missing from the index"
grep -qF 'source: PR #143' "$SC/$AGENT/surprising_gate.md" 2>/dev/null && ok "(c) the proposal's provenance survived into the stored entry" || no "(c) the provenance was dropped on promotion"

echo "== (c2) an incomplete / unreadable proposal is REFUSED, nothing written =="
PROP_BAD="$PROP_DIR/incomplete.md"
printf -- '---\nname: no_agent_named\ndescription: this proposal names no store to land in\n---\nbody\n' > "$PROP_BAD"
sum_c_before="$(store_sum "$SC")"
OUT="$(bash "$WRITER" --proposal "$PROP_BAD" --repo "$RC1" --store "$SC" --confirm < /dev/null 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "(c2) a proposal with no 'agent:' exits 2 (could-not-examine, never a silent pass)" || no "(c2) an incomplete proposal exited $RC, expected 2 — $OUT"
grep -qF 'REFUSE_PROPOSAL_INCOMPLETE' <<< "$OUT" && ok "(c2) the refusal carries a NAMED, greppable reason" || no "(c2) the refusal is unnamed: $OUT"
[ "$(store_sum "$SC")" = "$sum_c_before" ] && ok "(c2) the store is BYTE-IDENTICAL after the refusal" || no "(c2) the store changed on a refusal path"
OUT="$(bash "$WRITER" --proposal "$PROP_DIR/never-existed.md" --repo "$RC1" --store "$SC" --confirm < /dev/null 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "(c2) an ABSENT proposal exits 2" || no "(c2) an absent proposal exited $RC, expected 2"
grep -qF 'REFUSE_PROPOSAL_ABSENT' <<< "$OUT" && ok "(c2) the absent-proposal refusal names itself (absent and unreadable are kept distinct)" || no "(c2) the absent-proposal refusal is unnamed: $OUT"

# ---------------------------------------------------------------------------
# (d) AC1 — the five checks, on THIS writer.
# ---------------------------------------------------------------------------
echo "== (d) AC1: each of the five checks refuses, names its reason, store byte-unchanged =="
RD="$(new_repo)"; SD="$RD/.claude/agent-memory"; DD="$SD/$AGENT"
# One clean write establishes the corpus the duplicate/contradiction checks compare against — and
# that corpus is now built from the store's ENTRY FILES (one line per entry: its `description:`
# plus its body), not from MEMORY.md. So the slug and title contribute NOTHING to the comparison,
# and this fixture deliberately shares no word with either: `ledger_gate` / "ledger gate" against a
# summary that never says "ledger" or "gate".
#
# That is not decoration, it is the assertion. Against the old MEMORY.md comparison the stored line
# was `- [ledger gate](ledger_gate.md) — <summary>`, whose extra `ledger`/`gate`/`md` tokens padded
# the stored token set and dropped this pair below the 90 threshold — so (d1) below would NOT have
# refused. (i2)'s M4 mutant pins exactly that, rather than leaving it as prose.
#
# The earlier version of this comment said the opposite and was honest about why: the summary was
# shaped to BORROW the slug's words so the weak comparison would still clear the threshold. Tuning
# a fixture to make a check pass is how a check goes green while not working, which is the class
# this suite exists to catch — so the fixture no longer compensates for the writer, and the writer
# no longer needs it to.
DUP_TEXT="a foreign postmortem record makes the write path withhold its negation until the allowlist resolves"
BD="$(mkbody "$RD/body-d.md" "")"
run "$RD" "$SD" "$AGENT" ledger_gate "$DUP_TEXT" "$BD" --source "PR #144" --title "ledger gate" --confirm
[ "$RC" -eq 0 ] && ok "(d) the seed write for the duplicate/contradiction corpus succeeded" || no "(d) the seed write exited $RC — the checks below would have no corpus: $OUT"
# assert_refusal <label> <expected-rc> <token> <args...>
# The byte-unchanged baseline is taken IMMEDIATELY BEFORE each run, never once for the whole group.
# A group-wide baseline makes every case after the first report "MUTATED the store" as soon as one
# case genuinely writes — five failures naming four innocent cases, which sends the reader hunting
# a defect that is not there. Each case now asserts only about its own invocation.
assert_refusal() {
  local label="$1" want_rc="$2" token="$3" before; shift 3
  before="$(store_sum "$SD")"
  run "$RD" "$SD" "$@"
  [ "$RC" -eq "$want_rc" ] && ok "$label exits $want_rc" || no "$label exited $RC, expected $want_rc — $OUT"
  grep -qF "$token" <<< "$OUT" && ok "$label names its reason ($token)" || no "$label did not name $token — $OUT"
  [ "$(store_sum "$SD")" = "$before" ] && ok "$label left the store BYTE-IDENTICAL" || no "$label MUTATED the store"
}

# assert_advisory <label> <token> <args...> — the same three assertions for the two ADVISORY checks,
# inverted where the design inverted them. dead-reference and cross-repo REPORT and never refuse (see
# validate-entry.sh's header for the six measured rounds of false refusals that bought that), so what
# this writer must do with one is: exit 0, PRINT the finding, and WRITE. The third assertion is the
# mirror image of assert_refusal's and is the one that matters most — "the store CHANGED" is what
# distinguishes a demoted check from a check that still blocks, and asserting only rc 0 would stay
# green if the advisory were deleted outright.
assert_advisory() {
  local label="$1" token="$2" before; shift 2
  before="$(store_sum "$SD")"
  run "$RD" "$SD" "$@"
  [ "$RC" -eq 0 ] && ok "$label exits 0 — an advisory check does not block the write" || no "$label exited $RC, expected 0 — $OUT"
  grep -qF "$token" <<< "$OUT" && ok "$label REPORTS its finding ($token)" || no "$label did not report $token — $OUT"
  [ "$(store_sum "$SD")" != "$before" ] && ok "$label WROTE the entry — the finding is a warning, not a refusal" || no "$label left the store unchanged, so it blocked after all"
}

BD1="$(mkbody "$RD/body-d1.md" "")"
assert_refusal "(d1) duplicate" 1 "REFUSE_DUPLICATE" \
  "$AGENT" ledger_gate_two "$DUP_TEXT" "$BD1" --source "PR #144" --confirm
assert_refusal "(d2) contradiction" 1 "REFUSE_CONTRADICTION" \
  "$AGENT" ledger_gate_three "a foreign postmortem record never makes the write path withhold its negation until the allowlist resolves" "$BD1" --source "PR #144" --confirm
assert_refusal "(d3) provenance" 1 "REFUSE_PROVENANCE" \
  "$AGENT" bare_claim "a plain unattributed observation about how the gate behaves under load" "$BD1" --confirm
assert_advisory "(d4) dead reference [ADVISORY]" "ADVISORY_DEAD_REFERENCE" \
  "$AGENT" dead_ref "the guard at loomwright/scripts/no-such-file-here.sh fires, per PR #145" "$BD1" --confirm

# The cross-repo check needs a RESOLVED allowlist, and it must come from the process environment —
# never from the live .supervisor/config.json, which this suite must not touch (R0). Layer 2 of
# setup-memory.sh's precedence is exactly that hook.
sum_d5="$(store_sum "$SD")"
OUT="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widget" bash "$WRITER" "$AGENT" cross_repo \
        "the rollout in otherco/othersvc repo is described in PR #146" "$BD1" --repo "$RD" --store "$SD" --confirm < /dev/null 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "(d5) cross-repo [ADVISORY] exits 0 — it does not block the write" || no "(d5) cross-repo exited $RC, expected 0 — $OUT"
grep -qF "ADVISORY_CROSS_REPO" <<< "$OUT" && ok "(d5) cross-repo REPORTS its finding (ADVISORY_CROSS_REPO)" || no "(d5) cross-repo did not report its finding — $OUT"
[ "$(store_sum "$SD")" != "$sum_d5" ] && ok "(d5) cross-repo WROTE the entry — the foreign citation is warned about, not refused" || no "(d5) cross-repo left the store unchanged, so it blocked after all"
# ...and the same token is SILENT once the allowlist contains it — so (d5) reads the list rather than
# warning about a hardcoded slug. With the check demoted, the exit status can no longer show this
# (both cases exit 0); the presence or absence of the REPORT is the only thing left that can, which
# is why this half now asserts on the output.
# The TEXT differs from the case above, deliberately: that case now WRITES (an advisory does not
# block), so re-submitting the same words would be refused by the DUPLICATE check and this half
# would be measuring duplicate instead of cross-repo. Same foreign slug, different sentence.
OUT="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widget:otherco/othersvc" bash "$WRITER" "$AGENT" cross_repo_allowed \
        "deployment cadence for the otherco/othersvc repo appears in issue #147 alongside its owners" "$BD1" --repo "$RD" --store "$SD" --confirm < /dev/null 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && ! grep -qF "ADVISORY_CROSS_REPO" <<< "$OUT"; } \
  && ok "(d5) the SAME entry draws NO cross-repo finding once 'otherco/othersvc' is in the allowlist — the check reads the list, it does not match a hardcoded token" \
  || no "(d5) the entry was still reported with the slug allowlisted (rc=$RC) — $OUT"

echo "== (d2) AC1 MUTATION CONTROL M2: with the validator CALL removed, a seeded duplicate is written =="
M2="$MUT_DIR/mutant-no-call.sh"
awk '/^# ---- VALIDATOR CALL BEGIN/{skip=1;next} /^# ---- VALIDATOR CALL END/{skip=0;next} skip{next} {print}' "$WRITER" > "$M2" \
  || setup_fail "could not build mutant M2"
n_all_orig="$(grep -c '^validate_entry_all ' "$WRITER" 2>/dev/null || true)"; [ -n "$n_all_orig" ] || n_all_orig=0
n_all_mut="$(grep -c '^validate_entry_all ' "$M2" 2>/dev/null || true)"; [ -n "$n_all_mut" ] || n_all_mut=0
if [ "$n_all_orig" -ge 1 ] && [ "$n_all_mut" -eq 0 ]; then
  ok "(d2) the mutation is NON-VACUOUS: the real writer has $n_all_orig validate_entry_all call site(s), the mutant has 0"
else
  no "(d2) the mutation changed nothing (orig=$n_all_orig, mutant=$n_all_mut) — the control below would prove nothing"
fi
grep -qF 'validate-entry.sh' "$M2" && ok "(d2) the mutant still SOURCES the validator — it models 'sources but never invokes', the shape a source-line grep cannot see" || no "(d2) the mutant lost the source line too, so it is not isolating the call site"
bash -n "$M2" 2>/dev/null && ok "(d2) the mutant still parses" || no "(d2) mutant M2 does not parse"
RD2="$(new_repo)"; SD2="$RD2/.claude/agent-memory"
BD2="$(mkbody "$RD2/body.md" "")"
run_with "$M2" "$RD2" "$SD2" "$AGENT" ledger_gate "$DUP_TEXT" "$BD2" --source "PR #144" --title "ledger gate" --confirm
run_with "$M2" "$RD2" "$SD2" "$AGENT" ledger_gate_two "$DUP_TEXT" "$BD2" --source "PR #144" --confirm
if [ "$RC" -eq 0 ] && [ -f "$SD2/$AGENT/ledger_gate_two.md" ]; then
  ok "(d2) M2 CONFIRMED: without the call site the duplicate IS written — AC1's fixtures go RED, so they pin the invocation and not merely the source line"
else
  no "(d2) the mutant still refused the duplicate (rc=$RC) — AC1's fixtures are passing for some reason other than the validator call"
fi

# ---------------------------------------------------------------------------
# (i) THE COMPARISON CORPUS IS THE ENTRY FILES, NOT MEMORY.md.
#
# Every duplicate/contradiction fixture above is SHORT — a one-line summary with an empty body —
# and short is precisely the size at which the old MEMORY.md comparison still worked. So none of
# them can see the defect this group exists for: an index line is `- [title](slug.md) —
# description` with the description truncated to 200 chars, while --entry is the whole summary+body
# up to the 4000-char cap. Overlap is scored shared / max(|new|, |stored|), so once an entry has
# real body content the denominator is the new entry and the numerator is capped by the truncated
# line; the ratio tracks the length ratio and never reaches 90 or 60. Both checks stop
# discriminating, silently, and a byte-for-byte repost of a stored body under a new slug is written
# with no refusal at all.
#
# The fixture here is therefore the REALISTIC size a curated entry actually is — a few hundred
# words — and not one crafted to be small enough for a weak comparison to survive. (i2) below
# points --store back at the index and proves this case goes RED, which is what makes it evidence
# rather than an assertion that the new code does something.
# ---------------------------------------------------------------------------
echo "== (i) a realistically-sized entry duplicating a stored BODY under a different slug is REFUSED =="
RI="$(new_repo)"; SI="$RI/.claude/agent-memory"; DI="$SI/$AGENT"

# Neither body cites a path, a repo slug or a `NAME #123` token: the dead-reference and cross-repo
# checks must have nothing to say here, so that a refusal below can only be the duplicate check.
BIG_A="$RI/big-a.md"
cat > "$BIG_A" <<'BIGA'
The comparison a write time check performs is only as good as the material it is handed. When the
corpus is a pointer index, every stored line is a truncated one sentence summary while the incoming
text is a full paragraph of several hundred words. Similarity is scored as the shared significant
tokens over the larger of the two token sets, so the denominator is dominated by the incoming
paragraph and the numerator is bounded by the truncated summary. The ratio collapses toward the
ratio of the two lengths and never approaches the threshold, however identical the underlying
material happens to be. Nothing about that failure is visible from outside the process. No error is
printed, no refusal is emitted, and the write lands looking exactly like a legitimate one. The store
grows a second copy of a lesson it already held, under a different name, and the next reader has no
way to tell which of the two was the one that was reviewed. The only tell was a fixture kept
deliberately short so that its own score would clear the bar, carrying a comment that explained the
arithmetic making the shortening necessary. That comment was the evidence: the author understood the
mechanism and tuned the example around it instead of stating the bound or repairing the comparison.
A check tuned into passing is worse than an absent one, because an absent check is visibly absent
while a tuned one reports a clean verdict every time it runs and accumulates trust it has not
earned. The repair is to compare the same kind of material on both sides, one line for each stored
entry, holding the summary and the body exactly as the incoming entry holds them.
BIGA
BIG_B="$RI/big-b.md"
cat > "$BIG_B" <<'BIGB'
A linked worktree carries a file where the main checkout carries a directory, and that single
difference is the whole basis of the guard. A worker running inside a linked tree has a complete
looking checkout and every command it runs succeeds, so nothing in the session suggests the work is
about to evaporate. It does evaporate: removing the tree removes everything written under it that
was never committed, and a curated store written there is exactly that kind of casualty. The guard
therefore resolves the root first and evaluates the resolved root rather than the current directory,
because an explicit override pointing at a linked tree is the same hazard wearing different clothes,
and a guard reading only the current directory would wave it straight through. The refusal is loud
and names itself, so a human reading the transcript learns why the write did not land and where to
run it instead. The permissive half is equally deliberate. Outside any repository the writer falls
back to the current directory and writes, because temporary sandboxes and fixture stores are
legitimate places to exercise the machinery and refusing them buys nothing at all. Two sibling
writers disagree on that point, and the disagreement is recorded rather than smoothed over, since a
reader assuming all six behave identically will be surprised in exactly one direction. The lesson
generalises past this one guard. Any property inferred from an environment rather than declared by
the caller needs a stated resolution order and a test for each layer of it, or the layer nobody
exercised becomes the one that fails in front of a user.
BIGB

run "$RI" "$SI" "$AGENT" corpus_seed "the similarity score collapses once the two sides are different sizes" "$BIG_A" --source "PR #155" --title "corpus seed" --confirm
[ "$RC" -eq 0 ] && ok "(i) the realistically-sized seed entry is ACCEPTED" || no "(i) the seed entry was refused ($RC) — the case below could not discriminate: $OUT"
sum_i="$(store_sum "$SI")"
# THE CASE: the SAME body, a DIFFERENT slug, a reworded summary. Under the old index comparison
# this is written; see (i2).
run "$RI" "$SI" "$AGENT" corpus_repost "the similarity score breaks down once the two sides differ in size" "$BIG_A" --source "PR #155" --confirm
[ "$RC" -eq 1 ] && ok "(i) a repost of the stored BODY under a different slug is REFUSED (exit 1, examined and violating)" || no "(i) the repost exited $RC, expected 1 — the duplicate check is not comparing against the stored entry: $OUT"
grep -qF 'REFUSE_DUPLICATE' <<< "$OUT" && ok "(i) the refusal names REFUSE_DUPLICATE" || no "(i) the refusal did not name REFUSE_DUPLICATE — $OUT"
[ -f "$DI/corpus_repost.md" ] && no "(i) the repost was WRITTEN" || ok "(i) the repost wrote no entry file"
[ "$(store_sum "$SI")" = "$sum_i" ] && ok "(i) the store is BYTE-IDENTICAL after the refusal (the derived corpus is staged outside the store, so it leaves no residue)" || no "(i) the store changed on the refusal path"
# THE FALSE-REFUSAL CONTROL, and it is not optional. Widening what the checks can see moves the
# risk to the opposite failure: a corpus that refuses everything long would pass the assertion above
# while blocking every legitimate write, and nothing else in this suite would notice.
run "$RI" "$SI" "$AGENT" corpus_distinct "a linked worktree is refused because an uncommitted store written there is lost" "$BIG_B" --source "PR #156" --confirm
[ "$RC" -eq 0 ] && ok "(i) a DIFFERENT entry of the same size is still ACCEPTED — the corpus discriminates, it does not merely refuse long entries" || no "(i) a genuinely different entry was refused ($RC) — the widened comparison is producing false refusals: $OUT"
[ -f "$DI/corpus_distinct.md" ] && ok "(i) and it landed in the store" || no "(i) the accepted entry is not in the store"

# (i3) UPDATE IN PLACE vs DUPLICATE — the distinction the corpus would otherwise erase, and the
# reason the entry being written is excluded from its own comparison. This writer supports updating
# an entry (it stashes the prior file so a failed read-back can restore it), and an update re-posts
# most of the entry's own text: with the entry left in the corpus, a ONE-WORD typo fix scored ~98%
# against itself and was REFUSED as a duplicate. That was a regression the corpus fix introduced,
# found by performing the operation rather than reasoning about it, so both directions are pinned
# here — a check that only proved the refusal would have shipped it.
echo "== (i3) an UPDATE in place is accepted; the same body under a DIFFERENT slug is still refused =="
RI4="$(new_repo)"; SI4="$RI4/.claude/agent-memory"
UPD_A="$RI4/upd-a.md"; UPD_B="$RI4/upd-b.md"
cat > "$UPD_A" <<'UPDA'
The guard resolves the repository root before evaluating it, so an explicit override pointing at a
linked tree is refused exactly as a bare current directory would be. The refusal names itself and
the store is left byte identical, because nothing is written until every check has returned.
UPDA
# the SAME entry with a one-word amendment — the smallest edit a curator actually makes
sed -e 's/byte identical/byte-identical/' "$UPD_A" > "$UPD_B"
UPD_SUM="the worktree guard evaluates the resolved root rather than the current directory"
run "$RI4" "$SI4" "$AGENT" guard_note "$UPD_SUM" "$UPD_A" --source "PR #161" --confirm
[ "$RC" -eq 0 ] && ok "(i3) the original entry is written" || no "(i3) the original entry was refused ($RC) — $OUT"
run "$RI4" "$SI4" "$AGENT" guard_note "$UPD_SUM" "$UPD_B" --source "PR #161" --confirm
[ "$RC" -eq 0 ] && ok "(i3) a one-word UPDATE under the SAME slug is ACCEPTED — an entry is not a duplicate of itself, so updating stays possible" || no "(i3) the update was refused ($RC) — the corpus is comparing the entry against itself and has broken update-in-place: $OUT"
grep -qF 'byte-identical' "$SI4/$AGENT/guard_note.md" 2>/dev/null && ok "(i3) and the update actually replaced the stored body" || no "(i3) the update reported success but the stored body is unchanged"
# ...and excluding SELF must not open a hole: the same body under a DIFFERENT slug is still a
# duplicate, because every OTHER entry stays in the corpus.
run "$RI4" "$SI4" "$AGENT" guard_note_copy "$UPD_SUM" "$UPD_B" --source "PR #161" --confirm
[ "$RC" -eq 1 ] && ok "(i3) the SAME body under a DIFFERENT slug is still REFUSED — excluding self excludes exactly one entry, not the check" || no "(i3) the copy under a new slug exited $RC, expected 1 — excluding self opened a hole: $OUT"
grep -qF 'REFUSE_DUPLICATE' <<< "$OUT" && ok "(i3) and it names REFUSE_DUPLICATE" || no "(i3) the refusal did not name REFUSE_DUPLICATE — $OUT"

echo "== (i2) MUTATION CONTROL M4: --store pointed back at MEMORY.md ⇒ the repost IS written =="
M4="$MUT_DIR/mutant-store-index.sh"
sed -e 's/--store "\$COMPARE_STORE"/--store "$INDEX"/' "$WRITER" > "$M4" || setup_fail "could not build mutant M4"
n_corp_orig="$(grep -cF -- '--store "$COMPARE_STORE"' "$WRITER" 2>/dev/null || true)"; [ -n "$n_corp_orig" ] || n_corp_orig=0
n_corp_mut="$(grep -cF -- '--store "$COMPARE_STORE"' "$M4" 2>/dev/null || true)"; [ -n "$n_corp_mut" ] || n_corp_mut=0
n_idx_mut="$(grep -cF -- '--store "$INDEX"' "$M4" 2>/dev/null || true)"; [ -n "$n_idx_mut" ] || n_idx_mut=0
if [ "$n_corp_orig" -ge 1 ] && [ "$n_corp_mut" -eq 0 ] && [ "$n_idx_mut" -ge 1 ]; then
  ok "(i2) the mutation is NON-VACUOUS: the real writer compares against the derived corpus at $n_corp_orig call site(s), the mutant against the index"
else
  no "(i2) the mutation did not take (corpus sites $n_corp_orig → $n_corp_mut, index sites $n_idx_mut) — the control below would prove nothing"
fi
bash -n "$M4" 2>/dev/null && ok "(i2) the mutant still parses (so a difference below is behavioural, not a syntax error)" || no "(i2) mutant M4 does not parse"
RI2="$(new_repo)"; SI2="$RI2/.claude/agent-memory"
run_with "$M4" "$RI2" "$SI2" "$AGENT" corpus_seed "the similarity score collapses once the two sides are different sizes" "$BIG_A" --source "PR #155" --title "corpus seed" --confirm
[ "$RC" -eq 0 ] && ok "(i2) the mutant accepts the seed entry (the fixture reaches the case under test)" || no "(i2) the mutant refused the seed ($RC) — the control below would prove nothing: $OUT"
run_with "$M4" "$RI2" "$SI2" "$AGENT" corpus_repost "the similarity score breaks down once the two sides differ in size" "$BIG_A" --source "PR #155" --confirm
if [ "$RC" -eq 0 ] && [ -f "$SI2/$AGENT/corpus_repost.md" ]; then
  ok "(i2) M4 CONFIRMED: comparing against MEMORY.md, the byte-for-byte repost IS written — (i) goes RED, so it pins the corpus and not merely the presence of a duplicate check"
else
  no "(i2) the mutant also refused the repost (rc=$RC) — (i) is passing for some reason other than the derived corpus, and proves nothing about it"
fi
# ...and the SHORT (d1) fixture goes RED under the same mutant, which is the claim the rewritten
# (d) comment makes: with the slug's own tokens padding the stored side, a summary sharing none of
# them falls under the 90 threshold. Asserted here rather than left as prose in a comment.
RI3="$(new_repo)"; SI3="$RI3/.claude/agent-memory"; BI3="$(mkbody "$RI3/body.md" "")"
run_with "$M4" "$RI3" "$SI3" "$AGENT" ledger_gate "$DUP_TEXT" "$BI3" --source "PR #144" --title "ledger gate" --confirm
run_with "$M4" "$RI3" "$SI3" "$AGENT" ledger_gate_two "$DUP_TEXT" "$BI3" --source "PR #144" --confirm
if [ "$RC" -eq 0 ] && [ -f "$SI3/$AGENT/ledger_gate_two.md" ]; then
  ok "(i2) and (d1)'s SHORT duplicate is written by the mutant too — the old comparison failed even on a one-line entry once the summary stopped borrowing the slug's words"
else
  no "(i2) the mutant refused the short duplicate (rc=$RC) — the rewritten (d) comment claims more than this suite checks"
fi

# ---------------------------------------------------------------------------
# (e) AC2 — a missing / unparseable / partially-loaded helper.
# ---------------------------------------------------------------------------
echo "== (e) AC2: absent, unparseable, truncated and sentinel-stripped validators all refuse =="
RE="$(new_repo)"; SE="$RE/.claude/agent-memory"
BE="$(mkbody "$RE/body-e.md")"
# Seed one real entry so the store is non-empty and a byte-unchanged assertion has something to say.
run "$RE" "$SE" "$AGENT" seed_entry "a seeded entry recorded during the review in PR #147" "$BE" --source "PR #147" --confirm
[ "$RC" -eq 0 ] && ok "(e) the seed write succeeded (so the byte-unchanged assertions below are not over an empty dir)" || no "(e) the seed write exited $RC — $OUT"
sum_e="$(store_sum "$SE")"

VDIR="$(mktmp)"
# (i) unparseable — a genuine syntax error, so `source` itself returns non-zero.
printf 'if [ ; then\n' > "$VDIR/unparseable.sh"
# (ii) truncated AT A FUNCTION BOUNDARY — this one PARSES CLEANLY and defines duplicate,
# contradiction and provenance but NOT dead_reference or cross_repo. It is the case a one-function
# `command -v` probe would wave through, and it is why clause (ii) probes all five.
awk '/^# ---- check 4: dead reference/{exit} {print}' "$VALIDATOR" > "$VDIR/truncated.sh"
# (iii) everything EXCEPT the trailing sentinel assignment. Parses, defines all five, but the
# contract sentinel never gets set — clause (iii)'s whole reason for existing.
grep -v '^VALIDATE_ENTRY_CONTRACT="' "$VALIDATOR" > "$VDIR/nosentinel.sh"

# Fixture self-checks: each broken validator must actually be broken IN THE WAY NAMED, or the
# assertion that follows it is testing a different thing than its label claims.
bash -n "$VDIR/unparseable.sh" 2>/dev/null && no "(e) the 'unparseable' fixture PARSES — it is not unparseable" || ok "(e) fixture check: the unparseable validator genuinely does not parse"
if bash -n "$VDIR/truncated.sh" 2>/dev/null; then
  if grep -q '^validate_provenance()' "$VDIR/truncated.sh" && ! grep -q '^validate_cross_repo_reference()' "$VDIR/truncated.sh"; then
    ok "(e) fixture check: the truncated validator PARSES yet defines only the first three checks — the half-loaded case a one-function probe would miss"
  else
    no "(e) the truncated fixture does not have the claimed shape (provenance present? cross-repo absent?)"
  fi
else
  no "(e) the truncated fixture does not parse — it would exercise clause (i), not clause (ii) as labelled"
fi
n_sent_orig="$(grep -c '^VALIDATE_ENTRY_CONTRACT="' "$VALIDATOR" 2>/dev/null || true)"; [ -n "$n_sent_orig" ] || n_sent_orig=0
n_sent_mut="$(grep -c '^VALIDATE_ENTRY_CONTRACT="' "$VDIR/nosentinel.sh" 2>/dev/null || true)"; [ -n "$n_sent_mut" ] || n_sent_mut=0
if [ "$n_sent_orig" -eq 1 ] && [ "$n_sent_mut" -eq 0 ] && grep -q '^validate_cross_repo_reference()' "$VDIR/nosentinel.sh"; then
  ok "(e) fixture check: the sentinel-stripped validator keeps all five checks and loses exactly the one sentinel line"
else
  no "(e) the sentinel-strip fixture is wrong (sentinel lines orig=$n_sent_orig mutant=$n_sent_mut)"
fi

assert_guard_refusal() {  # <label> <validator-path>
  local label="$1" vp="$2"
  OUT="$(WRITE_AGENT_MEMORY_VALIDATOR="$vp" bash "$WRITER" "$AGENT" guard_case \
          "an entry recorded while the helper was broken, per PR #148" "$BE" \
          --repo "$RE" --store "$SE" --source "PR #148" --confirm < /dev/null 2>&1)"; RC=$?
  [ "$RC" -eq 2 ] && ok "$label exits 2 (could-not-examine, never conflated with a clean pass)" || no "$label exited $RC, expected 2 — $OUT"
  grep -qF 'REFUSE_VALIDATOR_UNAVAILABLE' <<< "$OUT" && ok "$label emits the NAMED, greppable reason REFUSE_VALIDATOR_UNAVAILABLE" || no "$label did not emit the named reason — $OUT"
  [ "$(store_sum "$SE")" = "$sum_e" ] && ok "$label left the store BYTE-IDENTICAL" || no "$label MUTATED the store"
  [ -f "$SE/$AGENT/guard_case.md" ] && no "$label WROTE the entry anyway" || ok "$label wrote no entry file"
}
assert_guard_refusal "(e1) an ABSENT validator" "$VDIR/never-existed.sh"
assert_guard_refusal "(e2) an UNPARSEABLE validator (clause i)" "$VDIR/unparseable.sh"
assert_guard_refusal "(e3) a TRUNCATED validator that parses but defines only 3 of 5 checks (clause ii)" "$VDIR/truncated.sh"
assert_guard_refusal "(e4) a SENTINEL-STRIPPED validator, all five checks present (clause iii)" "$VDIR/nosentinel.sh"
# All three assertions are needed together: the writer commits via temp-file + atomic mv, so
# "byte-unchanged" alone is ALSO true of a plain crash and does not discriminate a refusal from one.
grep -qF 'REFUSE_VALIDATOR_UNAVAILABLE' "$WRITER" && ok "(e) the REFUSE_VALIDATOR_UNAVAILABLE token is present ON DISK in the writer, so the deterministic outputs gate can see the guard exists" || no "(e) the writer carries no REFUSE_VALIDATOR_UNAVAILABLE token"

# (e5) DECISION (b) AT THE WRITER LEVEL — an UNREADABLE STORED ENTRY is could-not-examine, never
# clean. The writer distinguishes absent (no prior entries: a real, clean verdict) from present-but-
# unreadable, and this asserts it carries that distinction through to its exit status rather than
# flattening both into "nothing to compare against, proceed". Absent-vs-unreadable collapsing into
# one `[ -r ]` test is the exact fail-open class this item exists to close, and every other case in
# this suite exercises the ABSENT half only — so without this the unreadable half is untested.
#
# RE-AIMED, deliberately: this case used to chmod 000 the store's MEMORY.md and assert the
# validator's own REFUSE_DUPLICATE_STORE_UNREADABLE. MEMORY.md is no longer what the entry is
# compared against — the corpus is built from the entry FILES — so an unreadable index is no longer
# a hole in anything, and asserting on it would be asserting on a path that carries no verdict. The
# property being pinned is unchanged ("a store member I could not read is not a clean comparison");
# it is now aimed at the file that actually IS the corpus, and the refusal fires one layer earlier,
# in the writer's corpus builder, with its own named token. The second half below pins the flip
# side, so the behaviour change is recorded by a check rather than only by this comment.
echo "== (e5) an UNREADABLE STORED ENTRY refuses as could-not-examine, not as clean =="
RE5="$(new_repo)"; SE5="$RE5/.claude/agent-memory"; BE5="$(mkbody "$RE5/body.md")"
run "$RE5" "$SE5" "$AGENT" seed_entry "a seeded entry recorded during the review in PR #152" "$BE5" --source "PR #152" --confirm
[ "$RC" -eq 0 ] && ok "(e5) the seed write succeeded, so there is a real stored ENTRY to make unreadable" || no "(e5) the seed write exited $RC — $OUT"
chmod 000 "$SE5/$AGENT/seed_entry.md" 2>/dev/null
if [ -r "$SE5/$AGENT/seed_entry.md" ]; then
  # Running as root (or on a filesystem ignoring the mode) — chmod 000 does not make a file
  # unreadable, so the assertion below would test nothing. Say so rather than passing silently.
  ok "(e5) SKIPPED: chmod 000 left the file readable (root, or a mode-ignoring filesystem) — not asserted rather than asserted vacuously"
else
  ok "(e5) fixture check: the stored entry is genuinely unreadable"
  sum_e5="$(store_sum "$SE5")"
  run "$RE5" "$SE5" "$AGENT" later_entry "a later entry recorded during the review in PR #153" "$BE5" --source "PR #153" --confirm
  [ "$RC" -eq 2 ] && ok "(e5) an unreadable stored entry exits 2 (could not examine) — NOT 0, and not the 1 of a real violation" || no "(e5) an unreadable stored entry exited $RC, expected 2 — $OUT"
  grep -qF 'REFUSE_STORE_ENTRY_UNREADABLE' <<< "$OUT" && ok "(e5) the refusal names the unreadable store member, distinguishing it from an ABSENT store (which is a clean verdict)" || no "(e5) the refusal did not name the unreadable store member — $OUT"
  grep -qF "$SE5/$AGENT/seed_entry.md" <<< "$OUT" && ok "(e5) the refusal names WHICH entry could not be read, so the hole is actionable rather than merely reported" || no "(e5) the refusal does not say which file — $OUT"
  [ -f "$SE5/$AGENT/later_entry.md" ] && no "(e5) the entry was written over a store that could not be examined" || ok "(e5) nothing was written"
  [ "$(store_sum "$SE5")" = "$sum_e5" ] && ok "(e5) the store is BYTE-IDENTICAL after the refusal" || no "(e5) the store changed on the could-not-examine path"
fi
chmod 644 "$SE5/$AGENT/seed_entry.md" 2>/dev/null || true
# ...and the FLIP SIDE, recorded rather than assumed: an unreadable MEMORY.md does NOT block a
# write any more. It is this writer's own regenerated output, excluded from the corpus, and the
# rebuild path already treats it as regenerable (it re-derives the whole index and only loses the
# human H1 title). Pinning it means the behaviour change is a checked fact, not a claim in a
# comment — and if some later change makes the index load-bearing again, this goes RED and says so.
chmod 000 "$SE5/$AGENT/MEMORY.md" 2>/dev/null
if [ -r "$SE5/$AGENT/MEMORY.md" ]; then
  ok "(e5b) SKIPPED: chmod 000 left MEMORY.md readable (root, or a mode-ignoring filesystem)"
else
  run "$RE5" "$SE5" "$AGENT" third_entry "a third entry recorded during the review in PR #154" "$BE5" --source "PR #154" --confirm
  [ "$RC" -eq 0 ] && ok "(e5b) an UNREADABLE MEMORY.md does not block the write: the index is this writer's own output, excluded from the corpus and rebuilt from the files on disk" || no "(e5b) an unreadable MEMORY.md exited $RC — the index is still being treated as the comparison corpus: $OUT"
  grep -qF '(third_entry.md)' "$SE5/$AGENT/MEMORY.md" 2>/dev/null && ok "(e5b) and the index was rebuilt over the unreadable one, naming the new entry" || no "(e5b) the index was not rebuilt"
fi
chmod 644 "$SE5/$AGENT/MEMORY.md" 2>/dev/null || true

echo "== (e2) AC2 MUTATION CONTROL M3: the guard replaced with '|| true' =="
M3="$MUT_DIR/mutant-or-true.sh"
awk '
  /^# ---- LOAD GUARD BEGIN/ { skip = 1; print ". \"$VALIDATOR\" || true"; next }
  /^# ---- LOAD GUARD END/   { skip = 0; next }
  skip { next }
  { print }
' "$WRITER" > "$M3" || setup_fail "could not build mutant M3"
n_tok_orig="$(grep -c 'REFUSE_VALIDATOR_UNAVAILABLE' "$WRITER" 2>/dev/null || true)"; [ -n "$n_tok_orig" ] || n_tok_orig=0
n_tok_mut="$(grep -c 'REFUSE_VALIDATOR_UNAVAILABLE' "$M3" 2>/dev/null || true)"; [ -n "$n_tok_mut" ] || n_tok_mut=0
if grep -qF '. "$VALIDATOR" || true' "$M3" && [ "$n_tok_mut" -lt "$n_tok_orig" ]; then
  ok "(e2) the mutation is NON-VACUOUS: the guard block is gone, the source line now carries the forbidden '|| true' ($n_tok_orig → $n_tok_mut refusal-token sites)"
else
  no "(e2) the mutation did not take (|| true present? token sites $n_tok_orig → $n_tok_mut) — the control below would prove nothing"
fi
bash -n "$M3" 2>/dev/null && ok "(e2) the mutant still parses" || no "(e2) mutant M3 does not parse"
RE2="$(new_repo)"; SE2="$RE2/.claude/agent-memory"
BE2="$(mkbody "$RE2/body.md")"
# (i) the NAMED-REASON half of AC2 goes RED for every broken helper...
m3_named=0
for v in "$VDIR/never-existed.sh" "$VDIR/unparseable.sh" "$VDIR/truncated.sh" "$VDIR/nosentinel.sh"; do
  OUT="$(WRITE_AGENT_MEMORY_VALIDATOR="$v" bash "$M3" "$AGENT" guard_case \
          "an entry recorded while the helper was broken, per PR #148" "$BE2" \
          --repo "$RE2" --store "$SE2" --source "PR #148" --confirm < /dev/null 2>&1)"; RC=$?
  grep -qF 'REFUSE_VALIDATOR_UNAVAILABLE' <<< "$OUT" && m3_named=$((m3_named+1))
done
[ "$m3_named" -eq 0 ] && ok "(e2) M3 CONFIRMED (part 1): with the guard replaced by '|| true' NONE of the four broken helpers produces the named refusal — AC2's reason assertion goes RED" || no "(e2) the mutant still named the refusal in $m3_named of 4 cases — AC2's reason assertion is not pinned by the guard"
# (ii) ...and the sentinel-stripped helper is USED UNCHECKED, so the write actually lands: the
# byte-unchanged and refusal-status halves go RED too, not merely the message.
RE3="$(new_repo)"; SE3="$RE3/.claude/agent-memory"; BE3="$(mkbody "$RE3/body.md")"
OUT="$(WRITE_AGENT_MEMORY_VALIDATOR="$VDIR/nosentinel.sh" bash "$M3" "$AGENT" guard_case \
        "an entry recorded while the helper was broken, per PR #148" "$BE3" \
        --repo "$RE3" --store "$SE3" --source "PR #148" --confirm < /dev/null 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ -f "$SE3/$AGENT/guard_case.md" ]; then
  ok "(e2) M3 CONFIRMED (part 2): the mutant accepts a validator whose contract sentinel never loaded and WRITES — all three AC2 assertions (status, reason, byte-unchanged) go RED at once"
else
  no "(e2) the mutant did not write (rc=$RC) — part 2 of the control did not discriminate"
fi

# ---------------------------------------------------------------------------
# (f) AC10c — the worktree guard, from birth.
# ---------------------------------------------------------------------------
echo "== (f) AC10c: a git worktree is refused with exit 3; the non-git fallback stays PERMISSIVE =="
RF="$(new_repo)"
WT="$ROOT/wt-$$"
if git -C "$RF" worktree add -q -b wt-branch "$WT" >/dev/null 2>&1 && [ -f "$WT/.git" ]; then
  ok "(f) fixture check: the linked worktree exists and its top level carries a .git FILE (the main checkout carries a directory) — the property the guard keys on"
  BF="$(mkbody "$RF/body-f.md")"
  # (f1) cwd INSIDE the worktree, no --repo: the resolved root is the worktree's own toplevel.
  OUT="$( cd "$WT" && bash "$WRITER" "$AGENT" wt_entry "an entry attempted from a worktree, per PR #149" "$BF" --source "PR #149" --confirm < /dev/null 2>&1 )"; RC=$?
  [ "$RC" -eq 3 ] && ok "(f1) a WORKTREE cwd is refused with exit 3" || no "(f1) a worktree cwd exited $RC, expected 3 — $OUT"
  grep -qF 'REFUSE_WORKTREE' <<< "$OUT" && ok "(f1) the worktree refusal is NAMED (REFUSE_WORKTREE)" || no "(f1) the worktree refusal is unnamed — $OUT"
  [ -d "$WT/.claude/agent-memory" ] && no "(f1) the refused write created a store inside the worktree" || ok "(f1) nothing was written inside the worktree"
  # (f2) an EXPLICIT --repo pointing at the worktree is refused too — a cwd-only guard would miss it.
  OUT="$(bash "$WRITER" "$AGENT" wt_entry "an entry attempted from a worktree, per PR #149" "$BF" --repo "$WT" --store "$WT/.claude/agent-memory" --source "PR #149" --confirm < /dev/null 2>&1)"; RC=$?
  [ "$RC" -eq 3 ] && ok "(f2) an EXPLICIT --repo pointing at a worktree is refused with exit 3 — the guard evaluates the RESOLVED root, not merely \$PWD" || no "(f2) an explicit worktree --repo exited $RC, expected 3 — $OUT"
  git -C "$RF" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT" 2>/dev/null
else
  no "(f) could not create a linked git worktree fixture — the AC10c assertions did not run (this is a fixture gap, not a pass)"
  rm -rf "$WT" 2>/dev/null
fi
# (f3) the NON-GIT-REPO fallback is PERMISSIVE. add-orientation.sh falls back to `pwd` outside a
# repo and write-lessons.sh's hard `exit 2` is deliberately NOT copied across (AC10b/AC10c pin the
# difference), so a plain temp dir must WRITE.
RF3="$(mktmp)"   # no git init — deliberately not a repo
BF3="$(mkbody "$RF3/body.md")"
run "$RF3" "$RF3/.claude/agent-memory" "$AGENT" nongit_entry "an entry written outside any git repo, per PR #150" "$BF3" --source "PR #150" --confirm
[ "$RC" -eq 0 ] && ok "(f3) a NON-GIT-REPO root is PERMISSIVE: the write succeeds (write-lessons.sh's hard exit 2 for this case is NOT copied)" || no "(f3) the non-git fallback refused with $RC — the permissive fallback was broken: $OUT"
grep -qF '(nongit_entry.md)' "$RF3/.claude/agent-memory/$AGENT/MEMORY.md" 2>/dev/null && ok "(f3) and the index was still rebuilt outside a repo" || no "(f3) the index was not rebuilt outside a repo"

# ---------------------------------------------------------------------------
# (g) the confirm-only gate, and (h) atomicity.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# (j) CONCURRENCY — the index rebuild is serialized, so overlapping writers cannot drop each other.
#
# DETERMINISTIC BY CONSTRUCTION, NOT BY TIMING LUCK. Two halves, and neither one waits on a race
# happening to happen:
#   (j1) N writers are launched at once and ALL N entries must appear in MEMORY.md. The assertion is
#        an invariant over the FINISHED STATE ("N files / N-1 pointers"), not an observation of an
#        interleaving, so it holds however the N processes happened to schedule — and it also pins
#        the two ways the new lock could break a previously-working writer: a deadlock (some writer
#        never returns) and a leaked lock directory. STATED HONESTLY: as a detector of the lost
#        UPDATE itself this half is probabilistic, not deterministic — measured against a
#        lock-stripped mutant it did not lose a pointer in 11 runs, because six writers started
#        together tend to finish in start order. It is the end-to-end sanity half. (j2)+(j3) are
#        where the mutual exclusion is actually proven.
#   (j2) the lock is DRIVEN, not raced: the lock directory is created by the test itself, so the
#        writer provably cannot acquire it, and the wait bound is turned down to 1s. The writer must
#        then REFUSE (exit 2) with a named reason and must NOT leave the entry file behind — the
#        "a failed rebuild is serious, not a skip" contract. Fully deterministic: no second process
#        is racing anything, the contended state is constructed.
#   (j3) MUTATION CONTROL M5 — the same held lock, against a writer with the lock ACQUISITION
#        stripped out. It writes straight through and rebuilds the index, proving (j2) discriminates
#        the lock rather than something else about the fixture.
# ---------------------------------------------------------------------------
echo "== (j) concurrency: overlapping writers cannot drop each other's index pointers =="
RJ="$(new_repo)"; SJ="$RJ/.claude/agent-memory"; DJ="$SJ/$AGENT"
mkdir -p "$DJ" || setup_fail "could not create the concurrency store dir $DJ"
NJ=6
# SIX SUBSTANTIVELY DIFFERENT ENTRIES, not six copies with a counter. Near-identical text would be
# refused by the duplicate/contradiction checks and the case would "pass" having written nothing —
# a vacuous concurrency test. Each summary and body below shares almost no vocabulary with the
# others, so every one of the six is a legitimate write and the index assertion is about the index.
j_text_1="a lock directory beats flock on macOS because flock is simply absent there"
j_text_2="removing a git worktree discards any scratch file that was never committed"
j_text_3="pattern substitution over a large string wedges quadratically under bash three two"
j_text_4="an emitter must always exit zero while a correctness gate must fail closed"
j_text_5="reading a detached process output immediately is a race against its own startup"
j_text_6="the doc currency gate verifies numbers claimed and cannot notice a claim omitted"
j_pids=""
for i in 1 2 3 4 5 6; do
  eval "j_t=\$j_text_$i"
  printf '%s\n' "$j_t" > "$RJ/body-j-$i.md" || setup_fail "could not stage concurrency body $i"
  bash "$WRITER" "$AGENT" "concurrent_$i" "$j_t" "$RJ/body-j-$i.md" \
    --repo "$RJ" --store "$SJ" --source "PR #152" --confirm < /dev/null > "$ROOT/j-$i.out" 2>&1 &
  j_pids="$j_pids $!"
done
j_rc_bad=0
for p in $j_pids; do wait "$p" || j_rc_bad=$((j_rc_bad+1)); done
[ "$j_rc_bad" -eq 0 ] && ok "(j1) all $NJ concurrent writes exited 0" || no "(j1) $j_rc_bad of $NJ concurrent writes failed — $(cat "$ROOT"/j-*.out 2>/dev/null)"
j_files=0; j_ptrs=0
for i in 1 2 3 4 5 6; do
  [ -f "$DJ/concurrent_$i.md" ] && j_files=$((j_files+1))
  grep -qF "(concurrent_$i.md)" "$DJ/MEMORY.md" 2>/dev/null && j_ptrs=$((j_ptrs+1))
done
[ "$j_files" -eq "$NJ" ] && ok "(j1) all $NJ entry files are on disk" || no "(j1) only $j_files of $NJ entry files landed"
if [ "$j_ptrs" -eq "$NJ" ]; then
  ok "(j1) the rebuilt MEMORY.md names ALL $NJ entries — no writer's index overwrote a newer one"
else
  no "(j1) MEMORY.md names only $j_ptrs of $NJ entries — a concurrent rebuild dropped $((NJ - j_ptrs)) pointer(s) while their files are still on disk (the exact invariant this writer exists to hold)"
fi
[ "$(index_pointers "$DJ/MEMORY.md")" = "$NJ" ] && ok "(j1) and it carries EXACTLY $NJ pointers (N files / N-1 pointers, MEMORY.md not indexing itself)" || no "(j1) the index carries $(index_pointers "$DJ/MEMORY.md") pointers, expected $NJ"
resid_j="$(find "$DJ" -name '.write-agent-memory.*' 2>/dev/null | wc -l | tr -d '[:space:]')"
[ "$resid_j" = "0" ] && ok "(j1) no lock dir or temp file survived the concurrent writes (the lock is released on every path)" || no "(j1) $resid_j .write-agent-memory.* artifact(s) left behind after the concurrent writes"

echo "== (j2) a lock it cannot acquire is a REFUSAL, never a silently skipped rebuild =="
RJ2="$(new_repo)"; SJ2="$RJ2/.claude/agent-memory"; DJ2="$SJ2/$AGENT"
BJ2="$(mkbody "$RJ2/body-j2.md")"
run "$RJ2" "$SJ2" "$AGENT" j2_seed "a seed entry written before the lock was held, per PR #153" "$BJ2" --source "PR #153" --confirm
[ "$RC" -eq 0 ] && ok "(j2) the seed write (lock free) succeeds" || no "(j2) the seed write failed with $RC — $OUT"
J2_LOCK="$DJ2/.write-agent-memory.lock"
if mkdir "$J2_LOCK" 2>/dev/null; then
  ok "(j2) the test holds the lock directory itself — the writer below provably cannot acquire it (driven, not raced)"
  OUT="$(AGENT_MEMORY_INDEX_LOCK_WAIT_SECS=1 bash "$WRITER" "$AGENT" j2_blocked \
          "an entry attempted while another writer held the index lock, per PR #153" "$BJ2" \
          --repo "$RJ2" --store "$SJ2" --source "PR #153" --confirm < /dev/null 2>&1)"; RC=$?
  [ "$RC" -eq 2 ] && ok "(j2) a lock it cannot acquire REFUSES with exit 2" || no "(j2) exited $RC, expected 2 — a failed rebuild must keep the severity the undo path already had: $OUT"
  grep -qF 'could not acquire the store lock' <<< "$OUT" && ok "(j2) the refusal NAMES the lock as the reason (not a generic rebuild failure)" || no "(j2) the refusal does not name the lock — $OUT"
  [ -f "$DJ2/j2_blocked.md" ] && no "(j2) the blocked entry file was LEFT BEHIND — the rebuild was skipped and the index/directory now disagree" || ok "(j2) the blocked entry file was removed by the undo path — the store never holds a file the index cannot name"
  [ -f "$DJ2/j2_seed.md" ] && ok "(j2) the pre-existing seed entry is untouched" || no "(j2) the refusal collaterally removed an unrelated entry"
  rmdir "$J2_LOCK" 2>/dev/null
  # And once the lock is free again the very same write succeeds — proving (j2) failed on the lock
  # and not on something else about the entry.
  run "$RJ2" "$SJ2" "$AGENT" j2_blocked "an entry attempted while another writer held the index lock, per PR #153" "$BJ2" --source "PR #153" --confirm
  [ "$RC" -eq 0 ] && grep -qF '(j2_blocked.md)' "$DJ2/MEMORY.md" 2>/dev/null \
    && ok "(j2) with the lock released the IDENTICAL write succeeds and is indexed — the refusal was the lock, nothing else" \
    || no "(j2) the same write still failed (rc=$RC) after the lock was released — (j2) was not discriminating the lock: $OUT"
else
  no "(j2) could not create the lock directory fixture at $J2_LOCK — the lock-contention assertions did not run (a fixture gap, not a pass)"
fi

echo "== (j3) MUTATION CONTROL M5: with the lock acquisition stripped, a held lock is ignored =="
M5="$MUT_DIR/mutant-no-lock.sh"
# Strip ONLY the acquisition inside the rebuild wrapper; the lock helpers, the release and the EXIT
# trap all stay, so the mutant differs from the real writer in exactly one behaviour: it does not
# wait for, or respect, a lock another writer holds.
n_acq_orig="$(grep -c '^[[:space:]]*acquire_index_lock "\$dir"' "$WRITER" 2>/dev/null || true)"; [ -n "$n_acq_orig" ] || n_acq_orig=0
sed -e '/^[[:space:]]*acquire_index_lock "\$dir"/s/.*/  :/' "$WRITER" > "$M5" || setup_fail "could not build mutant M5"
n_acq_mut="$(grep -c '^[[:space:]]*acquire_index_lock "\$dir"' "$M5" 2>/dev/null || true)"; [ -n "$n_acq_mut" ] || n_acq_mut=0
if [ "$n_acq_orig" -gt 0 ] && [ "$n_acq_mut" -eq 0 ]; then
  ok "(j3) the mutation is NON-VACUOUS: the rebuild wrapper's lock acquisition is gone ($n_acq_orig → $n_acq_mut sites)"
else
  no "(j3) the mutation did not take (acquisition sites $n_acq_orig → $n_acq_mut) — the control below would prove nothing"
fi
bash -n "$M5" 2>/dev/null && ok "(j3) the mutant still parses" || no "(j3) mutant M5 does not parse"
RJ3="$(new_repo)"; SJ3="$RJ3/.claude/agent-memory"; DJ3="$SJ3/$AGENT"
BJ3="$(mkbody "$RJ3/body-j3.md")"
mkdir -p "$DJ3" || setup_fail "could not create the M5 store dir $DJ3"
J3_LOCK="$DJ3/.write-agent-memory.lock"
if mkdir "$J3_LOCK" 2>/dev/null; then
  OUT="$(WRITE_AGENT_MEMORY_VALIDATOR="$VALIDATOR" AGENT_MEMORY_INDEX_LOCK_WAIT_SECS=1 \
          bash "$M5" "$AGENT" j3_entry \
          "an entry written by a writer that ignores the store lock entirely, per PR #154" "$BJ3" \
          --repo "$RJ3" --store "$SJ3" --source "PR #154" --confirm < /dev/null 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && grep -qF '(j3_entry.md)' "$DJ3/MEMORY.md" 2>/dev/null; then
    ok "(j3) M5 CONFIRMED: without the acquisition the mutant rebuilds MEMORY.md while another writer holds the lock — (j2)'s refusal is caused by the lock and nothing else"
  else
    no "(j3) the mutant did NOT write through the held lock (rc=$RC) — (j2) is passing for some other reason and is vacuous: $OUT"
  fi
  rmdir "$J3_LOCK" 2>/dev/null
else
  no "(j3) could not create the M5 lock fixture at $J3_LOCK — the mutation control did not run (a fixture gap, not a pass)"
fi

echo "== (g) the confirm-only gate: a non-TTY run WITHOUT --confirm writes nothing =="
RG="$(new_repo)"; SG="$RG/.claude/agent-memory"
BG="$(mkbody "$RG/body-g.md")"
run "$RG" "$SG" "$AGENT" dry_entry "an entry offered without confirmation, per PR #151" "$BG" --source "PR #151"
[ "$RC" -eq 0 ] && ok "(g) the dry-run exits 0" || no "(g) the dry-run exited $RC — $OUT"
grep -qF 'PLANNED WRITE' <<< "$OUT" && ok "(g) the dry-run prints the plan" || no "(g) the dry-run printed no plan — $OUT"
[ -f "$SG/$AGENT/dry_entry.md" ] && no "(g) the dry-run WROTE the entry — an automated non-TTY run can mutate the store" || ok "(g) the dry-run wrote NOTHING"

echo "== (h) atomicity: no temp residue after a successful write =="
resid="$(find "$SA" -name '.write-agent-memory.*' 2>/dev/null | wc -l | tr -d '[:space:]')"
[ "$resid" = "0" ] && ok "(h) no .write-agent-memory.* temp residue in the store after successful writes" || no "(h) $resid temp file(s) left behind in the store"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
