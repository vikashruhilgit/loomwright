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
  ve_refused "AC1 $label:" 1 "$tok" "$st" "$VETMP/before"
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
ve_case "dead-reference" "$VE_DEAD"  "$VE_SRC"   "REFUSE_DEAD_REFERENCE"
ve_case "cross-repo"     "$VE_XREPO" "$VE_SRC"   "REFUSE_CROSS_REPO" "$VE_OURS"

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

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
