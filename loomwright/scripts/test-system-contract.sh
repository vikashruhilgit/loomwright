#!/usr/bin/env bash
# test-system-contract.sh — self-tests for the System Twin contract read/write gate (v14.10.0).
# Runs in isolated temp git repos (never touches the real .supervisor/twin). Mirrors
# test-project-memory.sh convention. Exit 0 = all pass, 1 = any failure.
#
# Covers the design's test matrix:
#   1. worktree-guard (MERGE BLOCKER — sole-writer/pinned-CWD enforcement)
#   2. valid write + read round-trip (contract emitted + advisory banner)
#   3. poison drop (un-provenanced contract file not emitted, drop logged)
#   4. provenance tamper-detection (broken hash chain → affected entries distrusted)
#   5. write-time eviction (contract-file cap honored)
#   6. .gitignore coverage of .supervisor/twin/ (checked against the real repo)
#   7. dedup guard (unchanged contract body written once)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WRITE="$HERE/write-system-contract.sh"

# ---------------------------------------------------------------------------
# PROVENANCE IN FIXTURES (decision (f) / AC15 — provenance is STRICT and centralised in
# validate_provenance). An entry must cite what motivated it: a bare token like `s`, `test` or `ev`
# names nothing and is now REFUSED. These fixtures therefore pass a REAL reference. An earlier
# revision of this suite wrapped $WRITE in a shim that appended a provenanced --source to every
# call; that was deleted on review because it masked genuine refusals — a fixture whose entry was
# refused for an unrelated reason still went green. Sources are explicit and per-call now.
# ---------------------------------------------------------------------------
READ="$HERE/read-system-contract.sh"
REAL_REPO="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$TMP-wt" 2>/dev/null' EXIT
( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
    && echo init > f && git add f && git commit -qm init )

echo "== 1. worktree-guard (MERGE BLOCKER) =="
git -C "$TMP" worktree add -q "$TMP-wt" -b wt >/dev/null 2>&1
( cd "$TMP-wt" && echo '{"subsystem":"x"}' | bash "$WRITE" --subsystem "x" --source "session:fixture-0001" ) >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 3 ]; then ok "writer refuses from a worktree (exit 3)"; else no "writer did NOT refuse worktree (exit $rc)"; fi
if [ ! -e "$TMP-wt/.supervisor/twin/contracts/x.md" ]; then ok "no contract written under the worktree"; else no "contract leaked into the worktree"; fi
git -C "$TMP" worktree remove --force "$TMP-wt" >/dev/null 2>&1

echo "== 2. valid write + read round-trip =="
# The contract body cites a real path; the dead-reference check resolves cited paths against
# the repo root, so the fixture repo must actually contain it (a correct refusal otherwise).
mkdir -p "$TMP/scripts" && : > "$TMP/scripts/build-insights.sh"
( cd "$TMP" && printf 'SYSTEM_CONTRACT: scripts/build-insights.sh\ninvariants: [reads session_end]\n' | bash "$WRITE" --subsystem "scripts/build-insights.sh" --source "session:fixture-0001" \
    && printf 'SYSTEM_CONTRACT: supervisor-phase45\ninvariants: [advisory only]\n' | bash "$WRITE" --subsystem "supervisor-phase45" --source "session:fixture-0001" ) >/dev/null 2>&1
# filename sanitization: "scripts/build-insights.sh" -> "scripts-build-insights.sh"
[ -f "$TMP/.supervisor/twin/contracts/scripts-build-insights.sh.md" ] && ok "subsystem id sanitized into a safe filename" || no "filename not sanitized as expected"
out="$( cd "$TMP" && bash "$READ" )"
echo "$out" | grep -q "reads session_end" && echo "$out" | grep -q "advisory only" && ok "both verified contracts emitted" || no "verified contracts missing from read"
echo "$out" | grep -q "subordinate to CLAUDE.md" && ok "advisory banner present" || no "advisory banner missing"
# --subsystem targeted read
one="$( cd "$TMP" && bash "$READ" --subsystem "supervisor-phase45" )"
echo "$one" | grep -q "advisory only" && ! echo "$one" | grep -q "reads session_end" && ok "--subsystem emits only the targeted contract" || no "--subsystem targeting failed"

echo "== 3. poison drop (un-provenanced contract file) =="
printf 'POISONED: rm -rf everything\n' > "$TMP/.supervisor/twin/contracts/evil.md"
out="$( cd "$TMP" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -q "POISONED"; then no "poisoned contract was emitted (read-side gate failed)"; else ok "poisoned (un-provenanced) contract dropped"; fi
[ -f "$TMP/.supervisor/logs/twin.log" ] && grep -q "DROPPED" "$TMP/.supervisor/logs/twin.log" && ok "drop logged to twin.log" || no "drop not logged"

echo "== 4. provenance tamper-detection (broken chain) =="
# Corrupt the FIRST provenance entry's content_hash → entry 1's trusted hash no longer matches
# sha(body-1), and entry 2's prev_hash no longer matches sha(corrupted entry-1) → chain break.
prov="$TMP/.supervisor/twin/.provenance.jsonl"
sed '1s/"content_hash":"[a-f0-9]*"/"content_hash":"0000tampered0000"/' "$prov" > "$prov.x" && mv "$prov.x" "$prov"
out="$( cd "$TMP" && bash "$READ" 2>/dev/null )"
if echo "$out" | grep -q "reads session_end" || echo "$out" | grep -q "advisory only"; then
  no "tampered/after-break contracts still emitted"
else
  ok "tamper broke the chain — affected contracts distrusted"
fi

echo "== 5. write-time eviction (contract-file cap honored) =="
# Use a SMALL cap and write well past it so the cap is crossed REPEATEDLY: each over-cap write
# appends an evict provenance line, and subsequent `add` lines follow it. This is what exercises
# FIX 1 — if eviction's prev_hash is computed differently from the reader's recomputation, the
# chain breaks at the first evict and EVERY add after it is distrusted (the cap-crossing-drops-all
# bug). Writing 7 at cap 3 means adds 4..7 all follow broken evict links in the buggy version.
EVDIR="$(mktemp -d)"; ( cd "$EVDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
# Each body must be DISTINCT: --store is now the contracts corpus (one line per stored contract,
# this subsystem's own excluded), so seven contracts reading 'contract <n>' would be seven copies of
# the single significant token 'contract' and every write after the first would be refused as a
# duplicate — the cap would never be crossed and this section would assert nothing. The bodies below
# share no significant tokens, so this stays a test of eviction.
( cd "$EVDIR" && for i in 1 2 3 4 5 6 7; do printf 'subsystem alpha%s bravo%s charlie%s delta%s echo%s\n' "$i" "$i" "$i" "$i" "$i" | SYSTEM_TWIN_MAX_CONTRACTS=3 bash "$WRITE" --subsystem "sub$i" --source "session:fixture-0001" >/dev/null 2>&1; done )
cnt="$(find "$EVDIR/.supervisor/twin/contracts" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "${cnt:-0}" -eq 3 ]; then ok "capped at 3 contracts (wrote 7, evicted 4)"; else no "cap not enforced (have $cnt, want 3)"; fi
grep -q '"action":"evict"' "$EVDIR/.supervisor/twin/.provenance.jsonl" 2>/dev/null && ok "eviction recorded in provenance" || no "eviction not recorded"
# Post-eviction read-back: WHICHEVER 3 contracts survive MUST still verify through the read gate.
# This is the assertion that catches an eviction that breaks the provenance hash chain (FIX 1) —
# without it, crossing the cap can silently make read-system-contract.sh emit ZERO contracts.
# NOTE (order-independence): we deliberately do NOT assert WHICH subsystem was evicted. Eviction
# picks the oldest by mtime, and under coarse (e.g. 1s) filesystem timestamp granularity the order
# among same-second writes is undefined — asserting a specific victim would be CI-flaky. The
# correctness guarantees that matter (cap honored + chain intact across evictions) are order-free.
ev_out="$( cd "$EVDIR" && bash "$READ" 2>/dev/null )"
ev_total=0; ev_emitted=0
for f in "$EVDIR"/.supervisor/twin/contracts/*.md; do
  [ -f "$f" ] || continue
  ev_total=$((ev_total+1))
  sid="$(basename "$f" .md)"
  echo "$ev_out" | grep -q "### contract: $sid" && ev_emitted=$((ev_emitted+1))
done
if [ "$ev_total" -eq 3 ] && [ "$ev_emitted" -eq 3 ]; then ok "all $ev_total surviving contracts verify through the read gate after repeated eviction (chain intact, order-independent)"; else no "eviction broke the chain — $ev_emitted/$ev_total survivors verified through read gate"; fi
rm -rf "$EVDIR"

echo "== 6. .gitignore coverage (real repo) =="
if git -C "$REAL_REPO" check-ignore -q .supervisor/twin/contracts/x.md 2>/dev/null; then ok ".supervisor/twin/ is gitignored in the real repo"; else no ".supervisor/twin/ NOT gitignored"; fi

echo "== 7. dedup guard (unchanged contract body) =="
DDIR="$(mktemp -d)"; ( cd "$DDIR" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i )
( cd "$DDIR" && printf 'same body\n' | bash "$WRITE" --subsystem "dup" --source "session:fixture-0001" >/dev/null 2>&1; printf 'same body\n' | bash "$WRITE" --subsystem "dup" --source "session:fixture-0001" >/dev/null 2>&1 )
adds="$(grep -c '"action":"add"' "$DDIR/.supervisor/twin/.provenance.jsonl" 2>/dev/null)"; adds="${adds:-0}"
if [ "$adds" -eq 1 ]; then ok "identical contract body written once (dedup guard)"; else no "duplicate not deduped (have $adds add entries)"; fi
rm -rf "$DDIR"

# =============================================================================
# 8. AC1 / AC2 / AC10a — WRITE-TIME VALIDATION AT THIS WRITER'S CALL SITE.
#
# This is the smallest suite in the set, and that is exactly why the coverage here is the SAME depth
# as the other four rather than a thinner sample: a writer that `source`s validate-entry.sh and never
# invokes it passes both test-validate-entry.sh and every case above. Only per-writer seeded
# violations plus the call-site mutation control pin the CALL, and "the suite was short" is not a
# reason for this writer's call site to be the unproven one.
#
# THREE SEPARATE ASSERTIONS PER CASE (AC2), and the separation is the point: this writer commits via
# temp file + atomic `mv`, so "byte-unchanged" is ALSO true of a crash, an arg-parse rejection and a
# `command not found`. Each case asserts (i) the refusal EXIT STATUS, (ii) a NAMED, GREPPABLE reason
# on stderr, and (iii) the store byte-unchanged — via `cmp` against a saved copy, not a digest
# (`md5 -q` is BSD-only and this suite runs on Linux CI too).
# Long-form rationale for the shared fixture design lives in test-lessons.sh's equivalent section.
# =============================================================================
echo "== 8. AC1/AC2/AC10a: write-time validation at the write-system-contract call site =="
VETMP="$(mktemp -d)"
VEFILE="$HERE/validate-entry.sh"
VE_ERR="$VETMP/stderr"
VE_ALLOW=""
VESTORE=".supervisor/twin/contracts/ve.md"

ve_repo() {
  local r; r="$(mktemp -d "$VETMP/r.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}

# ve_write <repo> <body> <source> [validator-override] [writer-path] -> sets VE_RC, writes VE_ERR.
# The contract BODY is the validated entry and arrives on stdin, which is this writer's documented
# shape. An EMPTY validator-override leaves $WRITE_SYSTEM_CONTRACT_VALIDATOR empty, which is what
# makes the writer fall back to its own resolution — the real path, not a test-only one.
# $VE_SUBSYS is the subsystem the contract is written under — a global rather than another
# positional, so a case can vary ONE thing and leave everything else in place. It matters now that
# --store is the contracts corpus with THIS subsystem's own contract excluded: a seed and an attempt
# sharing a subsystem is an UPDATE (nothing to compare against), and a repost under a SECOND
# subsystem is the duplicate. Different operations, and the suite has to say which it means.
VE_SUBSYS="ve"
ve_write() {
  local repo="$1" txt="$2" src="$3" val="${4:-}" prog="${5:-$WRITE}"
  ( cd "$repo" \
      && if [ -n "$VE_ALLOW" ]; then export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$VE_ALLOW"; fi \
      && printf '%s\n' "$txt" \
         | WRITE_SYSTEM_CONTRACT_VALIDATOR="$val" bash "$prog" --subsystem "$VE_SUBSYS" --source "$src" \
  ) >/dev/null 2>"$VE_ERR"
  VE_RC=$?
}

ve_refused() { # <label> <want-rc> <want-token> <store> <saved-copy>
  local label="$1" wrc="$2" tok="$3" st="$4" b4="$5"
  if [ "$VE_RC" -eq "$wrc" ]; then ok "$label (i) refused with exit $wrc"
  else no "$label (i) exit $VE_RC, want $wrc"; fi
  if grep -q "$tok" "$VE_ERR" 2>/dev/null; then ok "$label (ii) stderr names $tok"
  else no "$label (ii) stderr does NOT name $tok — got: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"; fi
  if cmp -s "$st" "$b4"; then ok "$label (iii) store byte-unchanged"
  else no "$label (iii) the refusal MUTATED the store"; fi
}

# ve_advised — the SAME three assertions for an ADVISORY check, each inverted exactly where the
# design inverted it. dead-reference and cross-repo REPORT and never refuse (validate-entry.sh's
# header records the six measured rounds of false refusals that bought that), so the three facts to
# assert about one become: the writer exits 0, it PRINTS the finding, and the entry IS written.
# (iii) is the load-bearing one: "the store changed" is what separates a demoted check from a check
# that still blocks, and a test asserting only rc 0 would stay green if the warning were deleted.
ve_advised() { # <label> <want-token> <store> <saved-copy>
  local label="$1" tok="$2" st="$3" b4="$4"
  if [ "$VE_RC" -eq 0 ]; then ok "$label (i) exited 0 — an ADVISORY check does not block the write"
  else no "$label (i) exit $VE_RC, want 0 — an advisory check must not refuse"; fi
  if grep -q "$tok" "$VE_ERR" 2>/dev/null; then ok "$label (ii) stderr REPORTS $tok"
  else no "$label (ii) stderr does NOT report $tok — got: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"; fi
  if cmp -s "$st" "$b4"; then no "$label (iii) the store is UNCHANGED, so the advisory blocked the write after all"
  else ok "$label (iii) the entry WAS written — the finding is a warning, not a refusal"; fi
}

# Each seed violates EXACTLY ONE check, because validate_entry_all returns the FIRST non-zero verdict
# in a fixed order — a seed that tripped an earlier check would assert nothing about the later one.
# VE_DUP is a REORDERING of VE_BASE, not a repeat: this writer's own dedup guard (section 7 above)
# short-circuits an identical subsystem+body at exit 0 before the validator runs, so a byte-identical
# seed would test that short-circuit instead of the duplicate check.
VE_BASE="release candidates promote through staging validation before production rollout begins across every regional cluster"
VE_DUP="across every regional cluster release candidates promote through staging validation before production rollout begins"
VE_CON="release candidates never promote through staging validation before production rollout begins across every regional cluster"
VE_PROV="the shared cache layer warms lazily on its very first read"
VE_DEAD="the retry helper now lives at loomwright/scripts/no-such-helper-xyz.sh"
VE_XREPO="the same defect was fixed in OTHERSVC #146"
VE_CLEAN="observability dashboards refresh their panels whenever a new deployment finishes rolling out"
VE_SRC="session:ve-0001"
VE_OURS="vikashruhilgit/loomwright"

# The cross-repo allowlist is supplied through this test's OWN environment; the live
# .supervisor/config.json is never touched and no foreign slug is ever added to it (R0/R8).
ve_case() { # <label> <text> <source> <want-token> [allowlist] [attempt-subsystem]
  local label="$1" txt="$2" src="$3" tok="$4" allow="${5:-}" sub2="${6:-ve}"
  local r st; r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "$label — SEED FAILED (no contract artifact; the fixture asserts nothing)"; return; fi
  cp "$st" "$VETMP/before"
  VE_ALLOW="$allow"; VE_SUBSYS="$sub2"; ve_write "$r" "$txt" "$src"; VE_SUBSYS="ve"; VE_ALLOW=""
  # An ADVISORY_* token routes to ve_advised; everything else is still a refusal. One dispatch
  # point, so a case cannot be silently asserted against the wrong contract.
  case "$tok" in
    ADVISORY_*) ve_advised "AC1 $label:" "$tok" "$st" "$VETMP/before" ;;
    *)          ve_refused "AC1 $label:" 1 "$tok" "$st" "$VETMP/before" ;;
  esac
  if [ "$sub2" != "ve" ]; then
    if [ ! -e "$r/.supervisor/twin/contracts/$sub2.md" ]; then ok "AC1 $label: (iv) the refused contract was not created at $sub2.md"
    else no "AC1 $label: (iv) the refusal still wrote $sub2.md"; fi
  fi
}

ve_case "duplicate"      "$VE_DUP"   "$VE_SRC"   "REFUSE_DUPLICATE"     ""  "ve2"
ve_case "contradiction"  "$VE_CON"   "$VE_SRC"   "REFUSE_CONTRADICTION" ""  "ve2"
# --- AC1: the two controls this writer shipped without ----------------------------------------
# (a) A BYTE-IDENTICAL body reposted under a SECOND subsystem must REFUSE. This is the case the old
#     call site could not see: --store was "$CONTRACT", the file this write targets, so for a new
#     subsystem it pointed at an absent file and the comparison was vacuous. It is also the case the
#     writer's own content_hash short-circuit does NOT cover — that guard is per-subsystem, so under
#     a second subsystem it does not fire and only the validator can refuse. Asserted on rc=1 +
#     REFUSE_DUPLICATE precisely so the short-circuit cannot be mistaken for the check: the
#     short-circuit exits 0 and prints "unchanged ... skipping".
VED="$(ve_repo)"
ve_write "$VED" "$VE_BASE" "$VE_SRC"
if [ -f "$VED/$VESTORE" ]; then
  cp "$VED/$VESTORE" "$VETMP/before"
  VE_SUBSYS="ve2"; ve_write "$VED" "$VE_BASE" "$VE_SRC"; VE_SUBSYS="ve"
  if [ "$VE_RC" -eq 1 ] && grep -q REFUSE_DUPLICATE "$VE_ERR" 2>/dev/null \
     && [ ! -e "$VED/.supervisor/twin/contracts/ve2.md" ] \
     && cmp -s "$VED/$VESTORE" "$VETMP/before"; then
    ok "AC1 duplicate (a): a byte-identical contract reposted under a SECOND subsystem is REFUSED by the VALIDATOR (exit 1, REFUSE_DUPLICATE) — not by the per-subsystem hash short-circuit, which exits 0"
  else
    no "AC1 duplicate (a): the identical repost under a second subsystem was NOT refused (exit $VE_RC) — --store is not comparing against the contracts store: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-200)"
  fi
else
  no "AC1 duplicate (a) — SEED FAILED"
fi

# (b) A genuinely DIFFERENT contract under a second subsystem must still WRITE. The half that keeps
#     (a) honest: refusing everything would satisfy (a) and destroy the writer. A false refusal
#     blocks a legitimate write, which is the worse failure of the two.
VEN="$(ve_repo)"
ve_write "$VEN" "$VE_BASE" "$VE_SRC"
if [ -f "$VEN/$VESTORE" ]; then
  VE_SUBSYS="ve2"; ve_write "$VEN" "$VE_CLEAN" "$VE_SRC"; VE_SUBSYS="ve"
  if [ "$VE_RC" -eq 0 ] && [ -f "$VEN/.supervisor/twin/contracts/ve2.md" ]; then
    ok "AC1 no-false-refusal: an unrelated contract under a SECOND subsystem is still WRITTEN (the corpus refuses duplicates, not siblings)"
  else
    no "AC1 no-false-refusal: an unrelated second-subsystem contract was REFUSED (exit $VE_RC) — the corpus is blocking legitimate per-subsystem writes: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-200)"
  fi
else
  no "AC1 no-false-refusal — SEED FAILED"
fi

# (c) An UPDATE of the same subsystem, with changed text, must still write: the corpus excludes this
#     subsystem's own contract, which is what keeps a contract editable. Without the exclusion every
#     re-generation of an evolving contract would be refused as its own duplicate.
VEU="$(ve_repo)"
ve_write "$VEU" "$VE_BASE" "$VE_SRC"
if [ -f "$VEU/$VESTORE" ]; then
  ve_write "$VEU" "$VE_BASE and one further clause about regional failover" "$VE_SRC"
  if [ "$VE_RC" -eq 0 ] && grep -qF "regional failover" "$VEU/$VESTORE" 2>/dev/null; then
    ok "AC1 update: re-writing the SAME subsystem with near-identical text is an UPDATE, not a duplicate (the corpus excludes this subsystem's own contract)"
  else
    no "AC1 update: updating a contract in place was refused (exit $VE_RC) — the corpus self-exclusion is broken and no contract can be revised"
  fi
else
  no "AC1 update — SEED FAILED"
fi

ve_case "provenance"     "$VE_PROV"  "dreaming"  "REFUSE_PROVENANCE"
ve_case "dead-reference" "$VE_DEAD"  "$VE_SRC"   "ADVISORY_DEAD_REFERENCE"
ve_case "cross-repo"     "$VE_XREPO" "$VE_SRC"   "ADVISORY_CROSS_REPO" "$VE_OURS"

# AC2 — the degraded-helper shapes, each built from the REAL helper (so they cannot drift from it)
# and each aimed at a DIFFERENT clause of the three-clause load guard:
#   absent     -> the `[ -f ] || [ -r ]` pre-check
#   unparse    -> clause (i): a trailing syntax error makes `source` exit non-zero. Bash still
#                 defines every function above the error, so this shape has ALL five validators AND
#                 the sentinel — only the source status distinguishes it.
#   partial    -> clause (ii): cut above validate_dead_reference, so three validators are defined and
#                 validate_entry_all is not. This is the shape a one-function `command -v` probe
#                 would wave through as "examined and clean".
#   nosentinel -> clause (iii): everything defined and working, only the contract sentinel missing.
#                 Nothing but clause (iii) can catch it, which is why it is also the vehicle for the
#                 `|| true` mutation control below.
cp "$VEFILE" "$VETMP/unparse.sh"; printf '\nif [ ; then\n' >> "$VETMP/unparse.sh"
awk '/^validate_dead_reference\(\)/{exit} {print}'  "$VEFILE" > "$VETMP/partial.sh"
awk '/^VALIDATE_ENTRY_CONTRACT="/{exit} {print}'    "$VEFILE" > "$VETMP/nosentinel.sh"

if bash -n "$VETMP/partial.sh" 2>/dev/null && bash -n "$VETMP/nosentinel.sh" 2>/dev/null \
   && ! bash -n "$VETMP/unparse.sh" 2>/dev/null; then
  ok "AC2 fixtures: partial+nosentinel parse cleanly, unparse does not (each aimed at its own clause)"
else
  no "AC2 fixtures: a degraded-helper variant is not the shape it claims — the clause labels below are unreliable"
fi

ve_degraded() { # <label> <validator-path>; attempted with a CLEAN entry, so the ONLY reason to
                # refuse is the broken helper.
  local label="$1" val="$2" r st; r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  if [ ! -f "$st" ]; then no "AC2 $label — SEED FAILED"; return; fi
  cp "$st" "$VETMP/before"
  ve_write "$r" "$VE_CLEAN" "$VE_SRC" "$val"
  ve_refused "AC2 $label:" 2 "REFUSE_VALIDATOR_UNAVAILABLE" "$st" "$VETMP/before"
}
ve_degraded "helper absent"        "$VETMP/no-such-validator.sh"
ve_degraded "helper unparseable"   "$VETMP/unparse.sh"
ve_degraded "helper truncated"     "$VETMP/partial.sh"
ve_degraded "helper sentinel-less" "$VETMP/nosentinel.sh"

# MUTATION CONTROLS. Both mutants are COPIES in $VETMP: the writer on disk is never edited, which
# makes "this writer goes RED while the other four stay green" true by construction rather than by a
# sibling run — a temp-file copy provably cannot reach the other four writers. Each mutant is gated
# on being non-empty, actually different, and still parseable before anything is credited to it.
ve_mutant_ok() { # <file> <desc>
  if [ ! -s "$1" ];              then no "$2 — mutant is EMPTY (vacuous control)"; return 1; fi
  if cmp -s "$WRITE" "$1";       then no "$2 — mutation changed NOTHING (vacuous control)"; return 1; fi
  if ! bash -n "$1" 2>/dev/null; then no "$2 — mutant does not parse (vacuous control)"; return 1; fi
  return 0
}

# ---------------------------------------------------------------------------
# (n) THIS WRITER'S OWN CALL-SITE ADVISORY NOTICE — asserted on BOTH the path that writes and the
# path that does not, plus the mutation control that proves the pair is load-bearing.
#
# WHY THIS EXISTS AT ALL. The dead-reference and cross-repo cases above assert only that an
# `ADVISORY_*` token reaches stderr, and those tokens are printed by the check functions INSIDE
# validate_entry_all — so deleting this writer's own `validate_entry_advisory_notice` call left
# every one of them green. Measured before this block was written: the literal `THE WRITE PROCEEDED`
# appeared nowhere in this suite, so the call site had no test at all. With the two checks demoted
# to advisory, the REPORTING is the whole feature, and the notice is the half that re-states the
# finding where a human actually reads it — next to the fact that the write went ahead.
#
# HOW THE PAIR IS SHAPED FOR *THIS* WRITER, which is not the shape test-write-agent-memory.sh uses.
# That writer has a confirm gate, so its (d6a)/(d6b) pair is dry-run-vs-confirmed. This writer has
# NO dry-run: it emits the notice at its ONE terminal SUCCESS exit, after the commit has actually
# happened — so there is no not-yet-written path to compare against. So the two no-write halves
# here are the ones this writer really has —
# (n1) an ordinary CLEAN write, where the notice must stay silent because nothing was reported, and
# (n3) the content_hash dedup short-circuit, which returns before the validator runs at all and must
# never claim a write proceeded. Both are honest properties of the notice, and both are stated in
# this writer's own control flow rather than borrowed from a sibling's.
#
# WHICH HALF HAS TEETH, stated plainly rather than implied: (n1) and (n3) also pass against the
# mutant — an absent notice is absent on every path — so they pin the notice's SILENCE, not its
# existence. (n2) is the half that goes RED when the call is removed, and (n4) is what proves it.
# It is placed after ve_mutant_ok() rather than beside the advisory cases because it needs it.
# ---------------------------------------------------------------------------
echo "== the call-site advisory notice fires on the write path, and only there =="
# (n1) an ordinary CLEAN write draws no finding, so the notice must print NOTHING.
vnR1="$(ve_repo)"; vnS1="$vnR1/$VESTORE"
ve_write "$vnR1" "$VE_CLEAN" "$VE_SRC"
if [ "$VE_RC" -eq 0 ] && [ -f "$vnS1" ]; then
  ok "(n1) fixture: a clean contract is written (exit 0) — this really is the wrote-and-nothing-to-report path"
else
  no "(n1) fixture: the clean write did not land (exit $VE_RC) — the silence below would prove nothing: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
  no "(n1) an ordinary clean write printed the advisory notice — it must be silent when no check reported anything"
else
  ok "(n1) an ordinary clean write is SILENT — the notice prints nothing when there is nothing to report"
fi

# (n2) a write carrying an ADVISORY finding: the notice MUST fire, in this writer's own name, and
# its sentence must be true — the contract really is on disk.
vnR2="$(ve_repo)"; vnS2="$vnR2/$VESTORE"
ve_write "$vnR2" "$VE_DEAD" "$VE_SRC"
if [ "$VE_RC" -eq 0 ]; then ok "(n2) the advisory-carrying write exits 0"
else no "(n2) the advisory-carrying write exited $VE_RC, want 0 — $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"; fi
if grep -qF 'ADVISORY_DEAD_REFERENCE' "$VE_ERR" 2>/dev/null; then
  ok "(n2) fixture: the check's own ADVISORY token is present, so an advisory really did fire"
else
  no "(n2) fixture: no ADVISORY_DEAD_REFERENCE — the notice assertion below would be vacuous: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
  ok "(n2) the write DOES print the call-site advisory notice — the reporting half of the ADVISORY design is present on a genuine write"
else
  no "(n2) the advisory notice is absent from a real write — the reporting half was silently deleted: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qE '^write-system-contract: ADVISORY:' "$VE_ERR" 2>/dev/null; then
  ok "(n2) and it is spoken in write-system-contract's own name, not the helper's"
else
  no "(n2) the notice does not name this writer: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
fi
if grep -qF 'no-such-helper-xyz' "$vnS2" 2>/dev/null; then
  ok "(n2) and the contract really was stored — the notice's claim is true on this path"
else
  no "(n2) the notice claimed the write proceeded but no contract landed at $VESTORE"
fi

# (n3) the SAME body under the SAME subsystem: the content_hash short-circuit returns BEFORE the
# validator runs, so nothing is written — and a notice ending "THE WRITE PROCEEDED" would be a lie.
cp "$vnS2" "$VETMP/before-n3"
ve_write "$vnR2" "$VE_DEAD" "$VE_SRC"
if [ "$VE_RC" -eq 0 ] && cmp -s "$vnS2" "$VETMP/before-n3"; then
  ok "(n3) fixture: the repeat is the dedup short-circuit (exit 0, contract byte-identical) — this really is the wrote-nothing path"
else
  no "(n3) fixture: the repeat was not a silent no-op (exit $VE_RC, contract changed) — the assertion below is about a different path"
fi
if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
  no "(n3) a call that wrote NOTHING still claimed 'THE WRITE PROCEEDED'"
else
  ok "(n3) the no-op repeat does NOT claim 'THE WRITE PROCEEDED' — the notice never speaks for a write that did not happen"
fi

# (n4) MUTATION CONTROL: strip the call-site notice from a COPY and (n2) must go RED. `:` replaces
# the call rather than deleting the line, so that no enclosing block is left with an empty body — a
# bash syntax error would make the control prove a parse failure instead of a missing notice. The literal is the full call INCLUDING its argument, so the mutation cannot also hit the
# VALIDATOR_REQUIRED_FUNCS list — which names the same function and must survive, or the load guard
# would refuse and the mutant would fail for the wrong reason.
echo "== MUTATION CONTROL: with the call-site notice removed, (n2) goes RED =="
VN_CALL='validate_entry_advisory_notice "write-system-contract"'
vn_orig="$(grep -cF -- "$VN_CALL" "$WRITE" 2>/dev/null || true)"; [ -n "$vn_orig" ] || vn_orig=0
sed -e "s/$VN_CALL/:/" "$WRITE" > "$VETMP/mut-notice.sh"
vn_mut="$(grep -cF -- "$VN_CALL" "$VETMP/mut-notice.sh" 2>/dev/null || true)"; [ -n "$vn_mut" ] || vn_mut=0
vn_funcs="$(grep -c 'VALIDATOR_REQUIRED_FUNCS=' "$VETMP/mut-notice.sh" 2>/dev/null || true)"; [ -n "$vn_funcs" ] || vn_funcs=0
if [ "$vn_orig" -ge 1 ] && [ "$vn_mut" -eq 0 ] && [ "$vn_funcs" -ge 1 ]; then
  ok "(n4) the mutation is NON-VACUOUS: $vn_orig call site(s) in the writer, 0 in the mutant, and the required-funcs list survived"
else
  no "(n4) the mutation did not take as intended (call sites $vn_orig → $vn_mut, funcs list $vn_funcs) — the control below would prove nothing"
fi
if ve_mutant_ok "$VETMP/mut-notice.sh" "(n4) notice mutant"; then
  vnR4="$(ve_repo)"; vnS4="$vnR4/$VESTORE"
  ve_write "$vnR4" "$VE_DEAD" "$VE_SRC" "$VEFILE" "$VETMP/mut-notice.sh"
  if [ "$VE_RC" -eq 0 ] && grep -qF 'no-such-helper-xyz' "$vnS4" 2>/dev/null; then
    ok "(n4) the mutant still WRITES the entry — the only behavioural difference under test is the notice"
  else
    no "(n4) the mutant failed to write (exit $VE_RC) — the comparison would not be like-for-like: $(tr '\n' ' ' < "$VE_ERR" | cut -c1-160)"
  fi
  if grep -qF 'ADVISORY_DEAD_REFERENCE' "$VE_ERR" 2>/dev/null; then
    ok "(n4) and the check's OWN token is still printed by the mutant — which is exactly why the advisory cases above could not detect this deletion"
  else
    no "(n4) the mutant lost the check's own token too, so it is not the isolated mutation intended"
  fi
  if grep -qF 'THE WRITE PROCEEDED' "$VE_ERR" 2>/dev/null; then
    no "(n4) REFUTED: the notice appeared with its call site removed — (n2) is passing for some other reason and is vacuous"
  else
    ok "(n4) CONFIRMED: without the call site the notice VANISHES from a real write — (n2) goes RED without it and is load-bearing"
  fi
fi
rm -f "$VETMP/mut-notice.sh"   # a mutated writer must never outlive its own control

# (a) AC1's mandated per-writer control: script the VALIDATOR CALL block out. REPLACED with `:`
# rather than deleted, so no enclosing block is left with an empty body (a bash syntax error, and a
# mutant that cannot run proves nothing).
awk '/---- VALIDATOR CALL BEGIN/{s=1; print "  :"; next} /---- VALIDATOR CALL END/{s=0; next} !s' \
  "$WRITE" > "$VETMP/mut-call.sh"
if ve_mutant_ok "$VETMP/mut-call.sh" "AC1 call-site mutant"; then
  r="$(ve_repo)"; st="$r/$VESTORE"
  ve_write "$r" "$VE_BASE" "$VE_SRC"
  cp "$st" "$VETMP/before"
  ve_write "$r" "$VE_CON" "$VE_SRC" "$VEFILE" "$VETMP/mut-call.sh"
  if [ "$VE_RC" -eq 0 ] && ! cmp -s "$st" "$VETMP/before"; then
    ok "AC1 mutation control: deleting the VALIDATOR CALL lets the contradiction seed through (exit 0, store rewritten) — the fixtures above are RED because of the call site, not the source line"
  else
    no "AC1 mutation control: the call-site mutant STILL refused (exit $VE_RC) — the AC1 fixtures may be passing for some other reason"
  fi
fi

# (a2) THE CORPUS CONTROL: point --store back at "$CONTRACT" — the pre-fix call site — and the
# identical-repost assertion above must go RED. The rewrite is asserted by COUNT on both sides,
# because a mutation that missed a call site would leave the mutant behaving like the writer and the
# control would look green while proving nothing (the column-0 self-healing mutant this branch has
# already hit once). This is also what separates the validator from this writer's own content_hash
# short-circuit: the short-circuit is per-subsystem, so under a SECOND subsystem it never fires and
# the mutant writes the identical body straight through.
n_corp_orig="$(grep -cF -- '--store "$corpus_tmp"' "$WRITE" 2>/dev/null || true)"; [ -n "$n_corp_orig" ] || n_corp_orig=0
sed -e 's/--store "\$corpus_tmp"/--store "$CONTRACT"/g' "$WRITE" > "$VETMP/mut-store.sh"
n_corp_mut="$(grep -cF -- '--store "$corpus_tmp"' "$VETMP/mut-store.sh" 2>/dev/null || true)"; [ -n "$n_corp_mut" ] || n_corp_mut=0
n_ctr_mut="$(grep -cF -- '--store "$CONTRACT"' "$VETMP/mut-store.sh" 2>/dev/null || true)"; [ -n "$n_ctr_mut" ] || n_ctr_mut=0
if [ "$n_corp_orig" -ge 1 ] && [ "$n_corp_mut" -eq 0 ] && [ "$n_ctr_mut" -ge 1 ]; then
  ok "AC1 corpus control: the mutation is NON-VACUOUS ($n_corp_orig corpus call site(s) in the writer, 0 in the mutant, $n_ctr_mut pointing at the target contract)"
else
  no "AC1 corpus control: the mutation did not take (corpus $n_corp_orig → $n_corp_mut, contract $n_ctr_mut) — the control below would prove nothing"
fi
if ve_mutant_ok "$VETMP/mut-store.sh" "AC1 corpus mutant"; then
  rM="$(ve_repo)"
  ve_write "$rM" "$VE_BASE" "$VE_SRC" "$VEFILE" "$VETMP/mut-store.sh"
  if [ "$VE_RC" -eq 0 ]; then
    VE_SUBSYS="ve2"; ve_write "$rM" "$VE_BASE" "$VE_SRC" "$VEFILE" "$VETMP/mut-store.sh"; VE_SUBSYS="ve"
    if [ "$VE_RC" -eq 0 ] && [ -f "$rM/.supervisor/twin/contracts/ve2.md" ]; then
      ok "AC1 corpus control CONFIRMED: with --store back on the target contract file, the byte-identical repost under a second subsystem IS written — the duplicate assertions above pin the corpus, and the hash short-circuit does not cover this case"
    else
      no "AC1 corpus control: the mutant also refused the repost (exit $VE_RC) — the duplicate assertions may be passing for some other reason"
    fi
  else
    no "AC1 corpus control: the mutant refused the SEED (exit $VE_RC) — the control never reached the case under test"
  fi
fi

# (b) AC2's mandated control: replace the whole load guard with the repo's pervasive `|| true`
# convention — the one line decision (a) forbids on the source. Paired with the sentinel-less helper
# because that is the shape where the mutation is OBSERVABLE: with an absent or truncated helper the
# writer still fails closed by accident (validate_entry_all is undefined, the call returns 127, the
# writer exits 2 with no named reason), but with a sentinel-less helper every validator works, so
# dropping the guard lets an UNVERIFIED-CONTRACT write go all the way through. All three AC2
# assertions go RED at once: exit 0, no named reason, store MUTATED.
awk '/---- LOAD GUARD BEGIN/{s=1; print "  . \"$VALIDATOR\" || true"; next} /---- LOAD GUARD END/{s=0; next} !s' \
  "$WRITE" > "$VETMP/mut-guard.sh"
if ve_mutant_ok "$VETMP/mut-guard.sh" "AC2 load-guard mutant"; then
  if grep -q '|| true' "$VETMP/mut-guard.sh"; then
    r="$(ve_repo)"; st="$r/$VESTORE"
    ve_write "$r" "$VE_BASE" "$VE_SRC"
    cp "$st" "$VETMP/before"
    ve_write "$r" "$VE_CLEAN" "$VE_SRC" "$VETMP/nosentinel.sh" "$VETMP/mut-guard.sh"
    if [ "$VE_RC" -eq 0 ] && ! grep -q REFUSE_VALIDATOR_UNAVAILABLE "$VE_ERR" 2>/dev/null \
       && ! cmp -s "$st" "$VETMP/before"; then
      ok "AC2 mutation control: replacing the load guard with '|| true' turns all three assertions RED (exit 0, no named reason, store mutated)"
    else
      no "AC2 mutation control: the '|| true' mutant did not go RED (exit $VE_RC) — AC2 may be passing for some other reason"
    fi
  else
    no "AC2 mutation control: the '|| true' replacement did not land in the mutant"
  fi
fi

# AC10a — RE-VERIFICATION, with one assertion section 1 does not make. Section 1 proves a worktree
# CWD is refused with exit 3; this proves the worktree guard still runs BEFORE the validator load
# guard, i.e. wiring the validator in did not reorder them. With a deliberately absent validator the
# refusal must STILL be the worktree's exit 3, never the load guard's exit 2 — otherwise the
# sole-writer/pinned-CWD refusal would be masked by AC2's.
VEWT="$(ve_repo)"
git -C "$VEWT" worktree add -q "$VEWT-wt" -b vewt >/dev/null 2>&1
if [ -d "$VEWT-wt" ]; then
  ve_write "$VEWT-wt" "$VE_CLEAN" "$VE_SRC" "$VETMP/no-such-validator.sh"
  if [ "$VE_RC" -eq 3 ] && grep -q worktree "$VE_ERR" 2>/dev/null; then
    ok "AC10a: a worktree CWD still refuses with exit 3, ahead of the validator load guard (absent helper does not mask it)"
  else
    no "AC10a: worktree refusal is exit $VE_RC (want 3) — the validator guard now precedes the worktree guard"
  fi
  [ -e "$VEWT-wt/$VESTORE" ] && no "AC10a: a contract leaked into the worktree" \
    || ok "AC10a: nothing written under the worktree"
  git -C "$VEWT" worktree remove --force "$VEWT-wt" >/dev/null 2>&1
else
  no "AC10a: could not create the fixture worktree — the assertion would be vacuous"
fi
rm -rf "$VETMP" "$VEWT-wt" 2>/dev/null

# ---------------------------------------------------------------------------
# (uf) UNRECOGNISED ARGUMENTS ARE REFUSED. A writer must be able to tell a caller it asked for
# something the writer does not implement, instead of dropping the argument and reporting success.
#
# WHY THIS EXISTS. write-system-contract.sh derives its store from the CURRENT DIRECTORY
# (`git rev-parse --show-toplevel`), never from anything the caller passes, and it takes NO
# positional arguments at all. Before the guard, `*) shift ;;` silently dropped every unmatched
# argument, so `--repo <elsewhere>` parsed, was discarded, and the contract landed in whatever repo
# the caller happened to be standing in — reported as a clean success at exit 0. Not hypothetical:
# a PR #144 review run did exactly that on the sibling lessons writer, believing `--repo` isolated
# the store, and a junk entry landed in this repo's real store and its provenance chain. `--repo`
# and `--store` are REAL flags on write-agent-memory.sh and add-orientation.sh, so reaching for one
# here is muscle memory from a sibling writer, not a typo.
#
# WHICH HALF HAS TEETH. (uf1) is the pin; (uf2) is the control proving the guard did not simply make
# the writer refuse everything. (uf3) is the mutation control: it restores the old `*) shift ;;` arm
# and asserts (uf1) goes RED, with a non-vacuity check that the sed landed.
# ---------------------------------------------------------------------------
echo "== 15. unrecognised arguments are refused, named, and write nothing =="
UFTMP="$(mktemp -d)"
UF_ERR="$UFTMP/stderr"
UF_SRC="PR #144"
UF_BODY="deployment rollbacks drain their connection pools before the health check flips"
uf_repo() {
  local r; r="$(mktemp -d "$UFTMP/r.XXXXXX")"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t \
      && echo init > f && git add f && git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$r"
}
# uf_run <repo> <writer-path> [args...] -> sets UF_RC, writes UF_ERR. The contract BODY arrives on
# stdin, which is this writer's documented shape.
# $UF_VALIDATOR mirrors ve_write's validator-override: a MUTANT copy lives in a temp dir, so its
# sibling-relative resolution of validate-entry.sh would fail and the writer would refuse with
# REFUSE_VALIDATOR_UNAVAILABLE — a refusal for the wrong reason, which would make the mutation
# control look green by accident. Left empty for the real writer, which must resolve it for itself.
UF_VALIDATOR=""
uf_run() {
  local repo="$1" prog="$2"; shift 2
  ( cd "$repo" && printf '%s\n' "$UF_BODY" \
      | WRITE_SYSTEM_CONTRACT_VALIDATOR="$UF_VALIDATOR" bash "$prog" "$@" ) >/dev/null 2>"$UF_ERR"
  UF_RC=$?
}
uf_err() { tr '\n' ' ' < "$UF_ERR" 2>/dev/null | cut -c1-200; }

# (uf1) THE DEFECT: a well-formed write PLUS two arguments this writer does not implement.
UFR1="$(uf_repo)"
uf_run "$UFR1" "$WRITE" --subsystem "$VE_SUBSYS" --source "$UF_SRC" \
       --repo /nonexistent/path --totally-made-up xyz
if [ "$UF_RC" -eq 2 ]; then
  ok "(uf1) an unrecognised argument is REFUSED with exit 2 — the could-not-examine convention this writer already uses for every other argument check"
else
  no "(uf1) exit $UF_RC, want 2 — the writer accepted an argument it does not implement: $(uf_err)"
fi
if grep -qF -- '--repo' "$UF_ERR" 2>/dev/null; then
  ok "(uf1) and the refusal NAMES the offending argument, so the caller learns which one was not honoured"
else
  no "(uf1) the refusal does not name '--repo' — an unnamed refusal cannot tell the caller what to fix: $(uf_err)"
fi
if grep -q '^write-system-contract: ' "$UF_ERR" 2>/dev/null; then
  ok "(uf1) and it is spoken in write-system-contract's own name"
else
  no "(uf1) the refusal does not name this writer: $(uf_err)"
fi
if [ -e "$UFR1/.supervisor" ]; then
  no "(uf1) the refusal still touched the store — a .supervisor/ tree exists after a refused write"
else
  ok "(uf1) and NOTHING was written — no .supervisor/ tree at all, so neither the store nor its provenance chain moved"
fi

# (uf2) CONTROL: the SAME invocation without the bogus arguments must still write. Without this, a
# writer that refused every invocation would pass (uf1).
UFR2="$(uf_repo)"
uf_run "$UFR2" "$WRITE" --subsystem "$VE_SUBSYS" --source "$UF_SRC"
if [ "$UF_RC" -eq 0 ] && [ -f "$UFR2/$VESTORE" ]; then
  ok "(uf2) CONTROL: the identical call WITHOUT the unrecognised arguments still writes (exit 0) — the guard refuses the unknown, not the known"
else
  no "(uf2) CONTROL FAILED: the real flags no longer write (exit $UF_RC) — the guard over-refuses: $(uf_err)"
fi

# (uf3) MUTATION CONTROL: restore the pre-fix `*) shift ;;` arm and (uf1) must go RED. The line is
# REPLACED rather than deleted, because a `case` pattern with no body is a syntax error and a mutant
# that cannot parse proves a broken mutant rather than a missing guard. The control asserts the
# mutant WRITES — not merely that it exits differently — so a refusal for some unrelated reason
# cannot be mistaken for the guard still working.
echo "== 15. MUTATION CONTROL: with the guard restored to silent-drop, (uf1) goes RED =="
UFMUT="$UFTMP/mut-noguard.sh"
uf_orig="$(grep -c "unrecognised argument" "$WRITE" 2>/dev/null || true)"; [ -n "$uf_orig" ] || uf_orig=0
sed -e "/unrecognised argument/s|.*|    *) shift ;;|" "$WRITE" > "$UFMUT"
uf_mut="$(grep -c "unrecognised argument" "$UFMUT" 2>/dev/null || true)"; [ -n "$uf_mut" ] || uf_mut=0
uf_drop="$(grep -c '^    \*) shift ;;$' "$UFMUT" 2>/dev/null || true)"; [ -n "$uf_drop" ] || uf_drop=0
if [ "$uf_orig" -eq 1 ] && [ "$uf_mut" -eq 0 ] && [ "$uf_drop" -eq 1 ]; then
  ok "(uf3) the mutation is NON-VACUOUS: 1 guard line in the real writer, 0 in the mutant, and the silent-drop arm is back in its place"
else
  no "(uf3) the mutation did not land as intended (guard $uf_orig → $uf_mut, silent-drop arm $uf_drop) — the control below would prove nothing"
fi
if bash -n "$UFMUT" 2>/dev/null; then
  ok "(uf3) the mutant still parses, so a difference below is behavioural rather than a syntax error"
  UFR3="$(uf_repo)"
  UF_VALIDATOR="$VEFILE"   # the mutant is a temp copy; point it at the real validator (see uf_run)
  uf_run "$UFR3" "$UFMUT" --subsystem "$VE_SUBSYS" --source "$UF_SRC" \
         --repo /nonexistent/path --totally-made-up xyz
  UF_VALIDATOR=""
  if [ "$UF_RC" -eq 0 ] && [ -f "$UFR3/$VESTORE" ]; then
    ok "(uf3) CONFIRMED: without the guard the SAME call exits 0 and writes the contract anyway — (uf1) goes RED without it and is load-bearing"
  else
    no "(uf3) REFUTED: the mutant refused too (exit $UF_RC) — (uf1) is passing for some other reason and is vacuous: $(uf_err)"
  fi
else
  no "(uf3) the mutant does not parse — it could not discriminate anything"
fi
rm -rf "$UFTMP" 2>/dev/null   # a mutated writer must never outlive its own control

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
