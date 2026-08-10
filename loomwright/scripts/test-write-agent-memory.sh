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
#   (f)  AC10c — a git WORKTREE cwd is refused with exit 3, an explicit --repo worktree too, and the
#        NON-GIT-REPO fallback stays PERMISSIVE (pwd), never write-lessons.sh's hard exit 2
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
# The call site is the only line at column 0 beginning `rebuild_memory_index ` (the DEFINITION line
# is `rebuild_memory_index() {`, with no space), so this edit removes the call and keeps the
# function — precisely the "sources it but never invokes it" shape the control has to model.
n_call_orig="$(grep -c '^rebuild_memory_index ' "$WRITER" 2>/dev/null || true)"; [ -n "$n_call_orig" ] || n_call_orig=0
sed -e '/^rebuild_memory_index /s/.*/:/' "$WRITER" > "$M1" || setup_fail "could not build mutant M1"
n_call_mut="$(grep -c '^rebuild_memory_index ' "$M1" 2>/dev/null || true)"; [ -n "$n_call_mut" ] || n_call_mut=0
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
# One clean write establishes the corpus the duplicate/contradiction checks compare against. The
# slug's own words appear in the summary on purpose: the index line the validator reads is
# `- [title](slug.md) — description`, so a slug contributing tokens the entry does not have would
# depress the similarity score and make the duplicate case pass for the wrong reason.
DUP_TEXT="the ledger gate withholds the negation whenever a foreign record is present in the ledger file"
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

BD1="$(mkbody "$RD/body-d1.md" "")"
assert_refusal "(d1) duplicate" 1 "REFUSE_DUPLICATE" \
  "$AGENT" ledger_gate_two "$DUP_TEXT" "$BD1" --source "PR #144" --confirm
assert_refusal "(d2) contradiction" 1 "REFUSE_CONTRADICTION" \
  "$AGENT" ledger_gate_three "the ledger gate never withholds the negation whenever a foreign record is present in the ledger file" "$BD1" --source "PR #144" --confirm
assert_refusal "(d3) provenance" 1 "REFUSE_PROVENANCE" \
  "$AGENT" bare_claim "a plain unattributed observation about how the gate behaves under load" "$BD1" --confirm
assert_refusal "(d4) dead reference" 1 "REFUSE_DEAD_REFERENCE" \
  "$AGENT" dead_ref "the guard at loomwright/scripts/no-such-file-here.sh fires, per PR #145" "$BD1" --confirm

# The cross-repo check needs a RESOLVED allowlist, and it must come from the process environment —
# never from the live .supervisor/config.json, which this suite must not touch (R0). Layer 2 of
# setup-memory.sh's precedence is exactly that hook.
sum_d5="$(store_sum "$SD")"
OUT="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widget" bash "$WRITER" "$AGENT" cross_repo \
        "the rollout in vendsy/hub repo is described in PR #146" "$BD1" --repo "$RD" --store "$SD" --confirm < /dev/null 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "(d5) cross-repo exits 1" || no "(d5) cross-repo exited $RC, expected 1 — $OUT"
grep -qF "REFUSE_CROSS_REPO" <<< "$OUT" && ok "(d5) cross-repo names its reason (REFUSE_CROSS_REPO)" || no "(d5) cross-repo did not name its reason — $OUT"
[ "$(store_sum "$SD")" = "$sum_d5" ] && ok "(d5) cross-repo left the store BYTE-IDENTICAL" || no "(d5) cross-repo MUTATED the store"
# ...and the same token PASSES once the allowlist contains it — so (d5) reads the list rather than
# pattern-matching a hardcoded slug.
OUT="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="acme/widget:vendsy/hub" bash "$WRITER" "$AGENT" cross_repo \
        "the rollout in vendsy/hub repo is described in PR #146" "$BD1" --repo "$RD" --store "$SD" --confirm < /dev/null 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "(d5) the SAME entry is ACCEPTED once 'vendsy/hub' is in the allowlist — the check reads the list, it does not match a hardcoded token" || no "(d5) the entry was still refused with the slug allowlisted ($RC) — $OUT"

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

# (e5) DECISION (b) AT THE WRITER LEVEL — an UNREADABLE index is could-not-examine, never clean.
# The validator distinguishes absent (no prior entries: a real, clean verdict) from present-but-
# unreadable, and this asserts the WRITER carries that distinction through to its exit status rather
# than flattening both into "nothing to compare against, proceed". Absent-vs-unreadable collapsing
# into one `[ -r ]` test is the exact fail-open class this item exists to close, and every other case
# in this suite exercises the ABSENT half only — so without this the unreadable half is untested.
echo "== (e5) an UNREADABLE index refuses as could-not-examine, not as clean =="
RE5="$(new_repo)"; SE5="$RE5/.claude/agent-memory"; BE5="$(mkbody "$RE5/body.md")"
run "$RE5" "$SE5" "$AGENT" seed_entry "a seeded entry recorded during the review in PR #152" "$BE5" --source "PR #152" --confirm
[ "$RC" -eq 0 ] && ok "(e5) the seed write succeeded, so there is a real MEMORY.md to make unreadable" || no "(e5) the seed write exited $RC — $OUT"
chmod 000 "$SE5/$AGENT/MEMORY.md" 2>/dev/null
if [ -r "$SE5/$AGENT/MEMORY.md" ]; then
  # Running as root (or on a filesystem ignoring the mode) — chmod 000 does not make a file
  # unreadable, so the assertion below would test nothing. Say so rather than passing silently.
  ok "(e5) SKIPPED: chmod 000 left the file readable (root, or a mode-ignoring filesystem) — not asserted rather than asserted vacuously"
else
  ok "(e5) fixture check: the index is genuinely unreadable"
  sum_e5="$(store_sum "$SE5")"
  run "$RE5" "$SE5" "$AGENT" later_entry "a later entry recorded during the review in PR #153" "$BE5" --source "PR #153" --confirm
  [ "$RC" -eq 2 ] && ok "(e5) an unreadable index exits 2 (could not examine) — NOT 0, and not the 1 of a real violation" || no "(e5) an unreadable index exited $RC, expected 2 — $OUT"
  grep -qF 'REFUSE_DUPLICATE_STORE_UNREADABLE' <<< "$OUT" && ok "(e5) the refusal names the unreadable store, distinguishing it from an ABSENT one (which is a clean verdict)" || no "(e5) the refusal did not name the unreadable store — $OUT"
  [ -f "$SE5/$AGENT/later_entry.md" ] && no "(e5) the entry was written over an index that could not be examined" || ok "(e5) nothing was written"
  [ "$(store_sum "$SE5")" = "$sum_e5" ] && ok "(e5) the store is BYTE-IDENTICAL after the refusal" || no "(e5) the store changed on the could-not-examine path"
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
