#!/usr/bin/env bash
# write-system-contract.sh — sole sanctioned WRITER for the System Twin contract store (v14.10.0).
#
# Writes a per-subsystem SYSTEM_CONTRACT artifact to
# .supervisor/twin/contracts/<subsystem-id>.md and appends a hash-chained provenance entry to
# .supervisor/twin/.provenance.jsonl. Writes atomically (temp + mv), enforces a contract-file
# cap via write-time eviction, and de-duplicates identical (subsystem + body) writes.
#
# .supervisor/twin/ is an ADVISORY artifact store like .supervisor/memory/ — subordinate to the
# human-authored CLAUDE.md; it is NEVER an enforcement boundary. Contracts are propose-only;
# conformance checks against them are advisory and NEVER block a PR or change a heal decision.
#
# SAFETY INVARIANT (sole-writer / pinned-CWD contract): this is the ONLY writer of
# .supervisor/twin/. It refuses to run from a git worktree (a linked worktree's top-level has a
# `.git` FILE, not a dir) with exit 3 — the ephemeral builder MUST run from the pinned repo-root
# CWD. A twin write inside a worktree would diverge and be lost on `git worktree remove`. The
# worktree check is the real enforcement, regardless of caller. Context-Keeper is NOT in this
# path: it handles state.md (sole writer on the parallel path; the inline main-thread Supervisor
# best-effort-writes state.md directly), never the twin store.
#
# NO --confirm GATE, DELIBERATELY. See AGENT_GUIDELINES.md §"Sole-writer confirm gates
# (committed-vs-gitignored rule)": a sole writer whose store is COMMITTED requires --confirm; one
# whose store is gitignored does not. `.supervisor/twin/` has no `!` negation in .gitignore and
# `git ls-files .supervisor/twin` returns nothing, so this writer is on the ungated side of that
# rule by design — it is not an asymmetry left over from the writers that DO gate
# (add-rule.sh, add-orientation.sh, write-agent-memory.sh, write-lessons.sh,
# write-project-memory.sh, all of whose stores are tracked). Do not "fix" it by adding a gate;
# if `.supervisor/twin/` ever becomes committed, the rule flips and a gate becomes required.
# Note also that sharing validate-entry.sh with the gated writers is NOT a gate — validation
# says an entry is well-formed, a confirm gate says a human asked for it.
#
# Usage:  write-system-contract.sh --subsystem "<id>" --contract-file <path> [--source "<id>"]
#         write-system-contract.sh --subsystem "<id>" --source "<id>"   # body on stdin
#         (the contract body is read from --contract-file if given, otherwise from stdin; the
#          body may be JSON or markdown — the store keeps it verbatim as the artifact.)
# Exit:   0 on success or safe no-op (e.g. no sha tool); 2 on a bad/would-corrupt call;
#         3 when refused from a git worktree (sole-writer/pinned-CWD violation).

set -uo pipefail

# ---------------------------------------------------------------------------
# WRITE-TIME VALIDATION — LOAD GUARD (decision (a) of the write-time-validation brief).
# See validate-entry.sh's LOAD GUARD CONTRACT. Three clauses, ALL required:
#   (i)   `. validate-entry.sh` must exit 0. `|| true` is FORBIDDEN on that line — discarding the
#         status IS the silent unvalidated append this design does not sanction. The status is
#         CAPTURED instead, and the caller's own errexit state is saved and restored around the
#         source so this block cannot change the shell options the rest of the script runs under.
#   (ii)  all five validator functions must be present. Bash defines every function ABOVE a syntax
#         error before aborting the parse, so a truncated helper leaves SOME validators defined —
#         a one-function probe would report "examined and clean" over half a validator.
#   (iii) $VALIDATE_ENTRY_CONTRACT must equal the HARDCODED literal below. Comparing against a
#         variable the helper exports (VALIDATE_ENTRY_CONTRACT_EXPECTED), or iterating the list it
#         exports ($VALIDATE_ENTRY_FUNCTIONS), would be CIRCULAR: both are assigned ABOVE the
#         sentinel, so a truncated copy could define them and pass its own test.
# Any shortfall is REFUSE_VALIDATOR_UNAVAILABLE, exit 2 (could-not-examine), nothing written.
# ---------------------------------------------------------------------------
REFUSE_VALIDATOR_UNAVAILABLE="REFUSE_VALIDATOR_UNAVAILABLE"
VALIDATE_ENTRY_CONTRACT_REQUIRED="validate-entry/2"
VALIDATOR_REQUIRED_FUNCS="validate_duplicate validate_contradiction validate_provenance validate_dead_reference validate_cross_repo_reference validate_entry_advisory_notice"

# Resolved BEFORE any `cd`: $0 may be relative, and three of these writers cd to the repo root.
VE_HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || printf '%s' ".")"

# _ve_load_validator — runs the three-clause guard. Called on the write path, never at parse time.
_ve_load_validator() {
  VALIDATOR="${WRITE_SYSTEM_CONTRACT_VALIDATOR:-}"
  if [ -z "$VALIDATOR" ]; then
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh" ]; then
      VALIDATOR="${CLAUDE_PLUGIN_ROOT}/scripts/validate-entry.sh"
    else
      VALIDATOR="$VE_HERE/validate-entry.sh"
    fi
  fi

  # ---- LOAD GUARD BEGIN -----------------------------------------------------
  # BEGIN/END delimit the guard as ONE replaceable unit so this suite's mandated mutation control
  # can replace it with `|| true` in a single edit and prove AC2 goes RED. Structural, not decor.
  if [ ! -f "$VALIDATOR" ] || [ ! -r "$VALIDATOR" ]; then
    printf '%s: %s — the shared write-time validator is missing or unreadable at "%s", so this entry could not be examined; refusing rather than appending it unvalidated. Nothing was written.
'       "write-system-contract" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" >&2
    exit 2
  fi

  # Clause (i). errexit is saved/restored rather than assumed: these five writers do not all run
  # under `set -e` (write-system-contract.sh is `set -uo pipefail`), so an unconditional `set -e`
  # here would silently change the failure semantics of everything downstream.
  case "$-" in *e*) _ve_had_e=1 ;; *) _ve_had_e=0 ;; esac
  set +e
  # shellcheck source=/dev/null
  . "$VALIDATOR"
  _ve_src_rc=$?
  if [ "$_ve_had_e" -eq 1 ]; then set -e; fi
  if [ "$_ve_src_rc" -ne 0 ]; then
    printf '%s: %s — sourcing the shared write-time validator "%s" failed (status %s: unparseable or truncated), so this entry could not be examined. Nothing was written.
'       "write-system-contract" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" "$_ve_src_rc" >&2
    exit 2
  fi

  # Clause (ii). All five are probed, plus the aggregate the call site actually uses — never one
  # name as a proxy for the rest.
  for _vef in $VALIDATOR_REQUIRED_FUNCS validate_entry_all; do
    if ! command -v "$_vef" >/dev/null 2>&1; then
      printf '%s: %s — the shared write-time validator loaded but "%s" is not defined (a partially-loaded validator would report "examined and clean" over half a check), so this entry could not be examined. Nothing was written.
'         "write-system-contract" "$REFUSE_VALIDATOR_UNAVAILABLE" "$_vef" >&2
      exit 2
    fi
  done

  # Clause (iii). Compared against the HARDCODED literal — see the circularity note above.
  if [ "${VALIDATE_ENTRY_CONTRACT:-}" != "$VALIDATE_ENTRY_CONTRACT_REQUIRED" ]; then
    printf '%s: %s — the shared write-time validator contract sentinel is "%s", not the expected "%s" (the file is truncated, or its contract changed), so this entry could not be examined. Nothing was written.
'       "write-system-contract" "$REFUSE_VALIDATOR_UNAVAILABLE" "${VALIDATE_ENTRY_CONTRACT:-<unset>}" "$VALIDATE_ENTRY_CONTRACT_REQUIRED" >&2
    exit 2
  fi
  # ---- LOAD GUARD END -------------------------------------------------------
}


SUBSYSTEM=""; CONTRACT_FILE=""; SOURCE="unknown"
while [ $# -gt 0 ]; do
  case "$1" in
    --subsystem)      SUBSYSTEM="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --subsystem=*)    SUBSYSTEM="${1#--subsystem=}"; shift ;;
    --contract-file)  CONTRACT_FILE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --contract-file=*) CONTRACT_FILE="${1#--contract-file=}"; shift ;;
    --source)         SOURCE="${2:-unknown}"; shift; [ $# -gt 0 ] && shift ;;
    --source=*)       SOURCE="${1#--source=}"; shift ;;
    # UNKNOWN-ARGUMENT REJECTION — exit 2, this writer's could-not-examine convention, nothing
    # written. This writer takes NO positional arguments, so anything unmatched above is something
    # the caller asked for that this writer does not implement, and the old `*) shift ;;` accepted
    # it and wrote anyway. That silence is not cosmetic here: the store is derived from the CURRENT
    # DIRECTORY (`git rev-parse --show-toplevel` below), so a caller who passes a store-redirecting
    # flag this writer has never had gets a successful-looking write into whatever repo they were
    # standing in. `--repo` and `--store` are REAL flags on write-agent-memory.sh and
    # add-orientation.sh — which is exactly how a caller reaches for one here — and a PR #144
    # review run did precisely that, landing a junk entry in this repo's real store.
    #
    # DO NOT HARMONISE THIS WITH validate-entry.sh's `_ve_parse_args`, which ignores unknown flags
    # ON PURPOSE. That is right for a VALIDATOR and wrong for a WRITER: a validator that refuses
    # costs a diagnostic on a fail-safe path, a writer that silently retargets costs the store.
    # Same vocabulary, opposite default — unifying the two parsers reopens this.
    *) echo "write-system-contract: unrecognised argument '$1' — refusing rather than writing to a curated store with an argument this writer does not implement (accepted: --subsystem, --contract-file, --source; see the usage header). Nothing was written." >&2; exit 2 ;;
  esac
done
[ -n "$SUBSYSTEM" ] || { echo "write-system-contract: --subsystem is required" >&2; exit 2; }
# Sanitize the source label of quotes/backslashes/control chars so the no-jq provenance fallback
# (printf-built JSON) can never emit malformed JSONL even if a caller widens --source.
SOURCE="$(printf '%s' "$SOURCE" | tr -d '"\\[:cntrl:]')"
[ -n "$SOURCE" ] || SOURCE="unknown"
# Sanitize the subsystem id for JSON the same way --source is, so the no-jq provenance fallback
# (printf-built JSON) can never emit malformed JSONL if a subsystem id contains " or \. The
# ORIGINAL $SUBSYSTEM is still used for the contract filename (SAFE_ID) and dedup logic; only the
# value that lands in provenance JSON is sanitized here.
SUBSYSTEM_JSON="$(printf '%s' "$SUBSYSTEM" | tr -d '"\\[:cntrl:]')"

# Sanitize the subsystem id into a safe filename: collapse path separators and anything that is
# not [A-Za-z0-9._-] into '-'. The logical id is preserved verbatim in the artifact body; this
# only governs the on-disk filename so e.g. "scripts/build-insights.sh" -> "scripts-build-insights.sh".
SAFE_ID="$(printf '%s' "$SUBSYSTEM" | tr '/' '-' | sed -E 's/[^A-Za-z0-9._-]/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
[ -n "$SAFE_ID" ] || { echo "write-system-contract: --subsystem '$SUBSYSTEM' sanitizes to an empty filename" >&2; exit 2; }

# ---- Worktree guard (sole-writer / pinned-CWD enforcement) ----------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$GITROOT" ] || { echo "write-system-contract: not inside a git repo — refusing" >&2; exit 2; }
# A linked worktree's top-level has a `.git` FILE ("gitdir: ..."); the main checkout has a dir.
if [ -f "$GITROOT/.git" ]; then
  # `.git` as a FILE = a linked WORKTREE or a git SUBMODULE top-level; both refused, both named.
  echo "write-system-contract: refusing to write from a non-primary checkout ($GITROOT) — its top-level '.git' is a FILE, which means either a linked git worktree or a git submodule. The twin store is written only from the pinned primary repo root (sole-writer/pinned-CWD contract)." >&2
  exit 3
fi
cd "$GITROOT" || { echo "write-system-contract: cannot cd to repo root" >&2; exit 2; }

# ---- Read the contract body (file or stdin) -------------------------------
if [ -n "$CONTRACT_FILE" ]; then
  [ -f "$CONTRACT_FILE" ] || { echo "write-system-contract: --contract-file '$CONTRACT_FILE' not found" >&2; exit 2; }
  BODY="$(cat "$CONTRACT_FILE")"
else
  BODY="$(cat)"   # stdin
fi
[ -n "$BODY" ] || { echo "write-system-contract: empty contract body (provide --contract-file or pipe on stdin)" >&2; exit 2; }

# ---- sha tool (fail-safe: no tool -> no write) ----------------------------
if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else
  echo "write-system-contract: no sha256 tool (sha256sum/shasum) — writes disabled, fail-safe no-op" >&2
  exit 0
fi

TWIN_DIR=".supervisor/twin"
CONTRACT_DIR="$TWIN_DIR/contracts"
PROV="$TWIN_DIR/.provenance.jsonl"
MAX_CONTRACTS="${SYSTEM_TWIN_MAX_CONTRACTS:-200}"   # overridable for tests; cap on #contract files
GENESIS="GENESIS"
CONTRACT="$CONTRACT_DIR/$SAFE_ID.md"

mkdir -p "$CONTRACT_DIR" 2>/dev/null || { echo "write-system-contract: cannot create $CONTRACT_DIR" >&2; exit 2; }
[ -f "$PROV" ] || : > "$PROV"

# ---------------------------------------------------------------------------
# THE VALIDATOR CALL SITE (see write-lessons.sh's for the shared rationale).
#
# WHAT --store POINTS AT, and why it is no longer the contract file this write targets. It used to
# be `--store "$CONTRACT"`, and that is the same defect write-agent-memory.sh fixed: a contract
# artifact is a DOCUMENT, so the validator was handed one document split into lines while --entry
# was a whole document. Both comparison checks score shared/max(|entry|,|line|), so every line's
# ceiling sat far under the 90/60 thresholds and the checks could only ever return "examined and
# clean". MEASURED on a live artifact: a contract compared against ITSELF scores 17%. The
# byte-identical repost that looked caught was caught by the content_hash short-circuit above, not
# by the validator — a green result there was never evidence the validator worked.
#
# So --store is the CONTRACTS CORPUS: one flattened line per stored contract, one per subsystem,
# with THIS subsystem's own contract excluded (an update re-posts most of its own text — the same
# self-exclusion, for the same reason, as build_compare_corpus() in write-agent-memory.sh).
#
# A CORPUS IS THE RIGHT CALL FOR THIS STORE, and it was checked rather than assumed. The worry is
# that per-subsystem artifacts might legitimately resemble each other, so a corpus would refuse
# honest writes. MEASURED over all 21 live contracts, pairwise: the highest same-polarity overlap is
# 56% (commands/setup.md vs skills/setup/SKILL.md — genuinely the same subsystem documented twice),
# well under the 90% duplicate threshold, and the highest OPPOSITE-polarity overlap is 0%, so the
# 60% contradiction threshold is unreachable across subsystems. There is real margin here, but it is
# a measurement of today's store, not a proof: if a future subsystem's contract is a near-copy of a
# sibling's, this writer will refuse it and name the sibling, and that refusal is the honest outcome
# to reconsider — NOT something to fix by handing --store a file that cannot discriminate.
# ---------------------------------------------------------------------------
_ve_load_validator

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# Temps live IN the twin dir (not $TMPDIR) so the commit `mv` is a same-filesystem, truly-atomic
# rename — a tmpfs /tmp (Linux/CI) would otherwise make `mv` a non-atomic cross-device copy+unlink,
# risking a truncated .provenance.jsonl on interruption.
c_tmp="$(mktemp "$CONTRACT_DIR/.ctmp.XXXXXX")"; prov_tmp="$(mktemp "$TWIN_DIR/.ptmp.XXXXXX")"
# The comparison corpus is staged in $TWIN_DIR, never in $CONTRACT_DIR: a file there would be
# counted by the eviction cap's `find ... -name '*.md'` and offered to `ls -1tr` as a victim.
corpus_tmp=""
trap 'rm -f "$c_tmp" "$prov_tmp" "$corpus_tmp" 2>/dev/null' EXIT

# Materialize the exact bytes that will land on disk, THEN hash them. Hashing the file (not the
# in-memory $BODY) keeps the writer's content_hash byte-identical to what the reader recomputes
# via `cat <file> | sha`, regardless of trailing-newline normalization by $(cat ...).
printf '%s\n' "$BODY" > "$c_tmp"
content_hash="$(cat "$c_tmp" | sha)"

# Dedup guard: the content_hash is body-derived. If the current verified contract for this
# subsystem already has the same content_hash, this is a no-op (avoids redundant chain growth).
if [ -f "$CONTRACT" ]; then
  existing_hash="$(cat "$CONTRACT" | sha)"
  if [ "$existing_hash" = "$content_hash" ]; then
    echo "write-system-contract: contract for '$SUBSYSTEM' unchanged (hash $content_hash) — skipping"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# AC18 — ORDERING. This call sits AFTER the writer's own idempotent dedup short-circuit, and that
# order is the whole point. The dedup guard above is a BENIGN NO-OP: re-writing an entry that is
# already stored is idempotence, not an error, and it has always exited 0. Running the validator
# first turned that into a hard REFUSE_DUPLICATE exit 1, so every idempotent caller (a re-run, a
# retry, a replayed queue item) started failing. The validator examines entries about to be
# WRITTEN; an entry that will not be written has nothing to validate. Moving this block back above
# the dedup guard reintroduces the regression — pinned by test.
# contract_compare_line <file> — a stored contract as ONE comparable line (the whole artifact
# flattened). Mirrors entry_compare_line() in write-agent-memory.sh; contracts carry no frontmatter,
# so there is nothing to select — only the flattening, and the leading `#`/`>`/`-` strip that keeps
# a body starting with a markdown heading from contributing NO line at all (the validator's store
# reader skips heading lines, so a corpus line must not start with one).
contract_compare_line() {
  awk '
    { b = b " " $0 }
    END {
      gsub(/[\r\t]/, " ", b); gsub(/  +/, " ", b)
      sub(/^[ ]+/, "", b); sub(/[ ]+$/, "", b); sub(/^[#>-]+[ ]*/, "", b)
      if (b ~ /[^ ]/) print b
    }
  ' "$1"
}

# build_compare_corpus <contracts-dir> <out-file> <self-path> — one line per stored contract, with
# this subsystem's own contract excluded. Return codes are write-agent-memory.sh's could-not-examine
# discipline: 0 usable (possibly empty) · 2 could not stage · 3 dir unlistable · 4 a contract exists
# but cannot be read (a hole in the corpus is never reported as clean).
build_compare_corpus() {
  local dir="$1" out="$2" self="${3:-}" f
  : > "$out" || return 2
  [ -d "$dir" ] || return 0
  [ -r "$dir" ] && [ -x "$dir" ] || return 3
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue                     # unmatched glob stays literal under bash 3.2
    [ -n "$self" ] && [ "$f" = "$self" ] && continue
    [ -r "$f" ] || { CORPUS_BAD_PATH="$f"; return 4; }
    contract_compare_line "$f" >> "$out" || return 2
  done
  return 0
}

corpus_tmp="$(mktemp "$TWIN_DIR/.corpus.XXXXXX")" || {
  echo "write-system-contract: refusing to write — the comparison corpus could not be staged in $TWIN_DIR, so this contract could not be compared against the store; refusing rather than reporting it clean. Nothing was written." >&2; exit 2; }
CORPUS_BAD_PATH=""
build_compare_corpus "$CONTRACT_DIR" "$corpus_tmp" "$CONTRACT"
corpus_rc=$?
case "$corpus_rc" in
  0) : ;;
  3) echo "write-system-contract: refusing to write — the contracts dir '$CONTRACT_DIR' exists but could not be listed, so the contracts this write would be compared against could not be examined; refusing rather than reporting it clean. Nothing was written." >&2; exit 2 ;;
  4) echo "write-system-contract: refusing to write — the stored contract '$CORPUS_BAD_PATH' exists but could not be read, so it could not be compared against — a hole in the corpus would make a duplicate or contradiction verdict of 'clean' meaningless. Nothing was written." >&2; exit 2 ;;
  *) echo "write-system-contract: refusing to write — the comparison corpus derived from '$CONTRACT_DIR' could not be staged (status $corpus_rc). Nothing was written." >&2; exit 2 ;;
esac

# ---- VALIDATOR CALL BEGIN ---------------------------------------------------
case "$-" in *e*) _ve_had_e=1 ;; *) _ve_had_e=0 ;; esac
set +e
validate_entry_all --entry "$BODY" --store "$corpus_tmp" \
  --source "$SOURCE" --root "$GITROOT"
_ve_rc=$?
if [ "$_ve_had_e" -eq 1 ]; then set -e; fi
# rc 0 IS NOT NECESSARILY SILENT. Two of the five checks (dead-reference, cross-repo) are ADVISORY:
# they report on stderr and never refuse, so a clean exit can still carry findings. A notice at the
# SUCCESS LINE repeats them in this writer's own voice, next to the fact that the write went ahead —
# a warning printed only inside the helper scrolls past, and an advisory nobody reads is worse than
# no check. It prints nothing when there is nothing to report.
# THE NOTICE IS NOT EMITTED HERE — see the note at the emission site below.
case "$_ve_rc" in
  0) : ;;
  1) echo "write-system-contract: refusing to write — the contract was examined and violates a write-time check (see the reason above). Nothing was written." >&2
     # A duplicate/contradiction reason quotes the store it compared against, and that is a temp
     # corpus path. Naming the real dir keeps the message actionable.
     echo "write-system-contract: (the store quoted above is the contracts corpus derived from $CONTRACT_DIR — one line per stored contract, this subsystem's own excluded.)" >&2
     exit 1 ;;
  *) echo "write-system-contract: refusing to write — the contract COULD NOT BE EXAMINED (see the reason above); refusing rather than reporting it clean. Nothing was written." >&2; exit 2 ;;
esac
# ---- VALIDATOR CALL END -----------------------------------------------------

last_line="$(tail -n1 "$PROV" 2>/dev/null || true)"
if [ -n "$last_line" ]; then prev_hash="$(printf '%s' "$last_line" | sha)"; else prev_hash="$GENESIS"; fi

# prov_line <subsystem> <prev_hash> <content_hash> <source> <action>
# Emits JSON with NO trailing newline; callers add exactly one via printf '%s\n'. (jq -nc would
# otherwise append its own newline → blank lines that break the hash chain.)
prov_line() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ss "$1" --arg ph "$2" --arg ch "$3" --arg src "$4" --arg act "$5" --arg ts "$ts" \
      '{subsystem:$ss,prev_hash:$ph,content_hash:$ch,source:$src,action:$act,written_at:$ts}' | tr -d '\n'
  else
    printf '{"subsystem":"%s","prev_hash":"%s","content_hash":"%s","source":"%s","action":"%s","written_at":"%s"}' "$1" "$2" "$3" "$4" "$5" "$ts"
  fi
}

cat "$PROV" > "$prov_tmp"
printf '%s\n' "$(prov_line "$SUBSYSTEM_JSON" "$prev_hash" "$content_hash" "$SOURCE" "add")" >> "$prov_tmp"

# Commit. Provenance FIRST: if the second rename fails, the worst case is a provenance entry with
# no matching contract file — which the read-side gate harmlessly ignores. A failed first rename
# leaves state untouched.
mv "$prov_tmp" "$PROV" && mv "$c_tmp" "$CONTRACT" || {
  echo "write-system-contract: atomic rename failed — write aborted; read gate ignores any unmatched provenance" >&2
  exit 2
}

# ---- Write-time eviction (cap on number of contract files; never silent) --
# NOTE: .provenance.jsonl is append-only (one line per add AND per evict), so each read walks the
# full chain (O(n)). Provenance compaction / re-genesis is a P4 follow-up — fine at the v1 scale.
count="$(find "$CONTRACT_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
while [ "${count:-0}" -gt "$MAX_CONTRACTS" ]; do
  # Evict the oldest contract file by mtime (excluding the one just written when possible).
  # SAFE: subsystem ids are sanitized to a filename-safe form ($SAFE_ID), so contract filenames
  # never contain spaces/newlines — the ls|head pipeline is fine for this controlled input.
  # ADVISORY ordering: under coarse filesystem mtime granularity (e.g. 1s on some CI), the order
  # among contracts written in the same tick is undefined, so the exact victim is not guaranteed.
  # That is acceptable for the foundation slice — eviction is advisory, and the cap + provenance
  # chain integrity (the correctness-critical invariants) hold regardless of which file is chosen.
  # A deterministic ledger-write-order eviction is a documented next-slice option.
  victim="$(ls -1tr "$CONTRACT_DIR"/*.md 2>/dev/null | head -n1)"
  [ -n "$victim" ] || break
  vid="$(basename "$victim" .md)"
  rm -f "$victim"
  eph="$(printf '%s' "$(tail -n1 "$PROV")" | sha)"
  printf '%s\n' "$(prov_line "$vid" "$eph" "" "eviction" "evict")" >> "$PROV"
  count="$(find "$CONTRACT_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
done

# THE ADVISORY NOTICE — emitted HERE, past the last reachable refusal and past the atomic commit,
# immediately before the success line. Its sentence ends "...and THE WRITE PROCEEDED", and the
# validator call site above is only on the write PATH: the atomic-rename failure still exits 2
# AFTER it, so emitting there printed "THE WRITE PROCEEDED" and then wrote nothing. This is the
# writer's ONLY success exit, so no genuine write can lose its warning; it is a no-op when nothing
# was reported, so it stays silent rather than wrong.
validate_entry_advisory_notice "write-system-contract"
echo "write-system-contract: stored contract for '$SUBSYSTEM' ($CONTRACT, hash $content_hash, source=$SOURCE)"
exit 0
