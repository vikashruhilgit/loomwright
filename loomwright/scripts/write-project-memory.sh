#!/usr/bin/env bash
# write-project-memory.sh — sole sanctioned WRITER for advisory project memory (v14.3.0).
#
# Appends a (human-approved) durable fact to .supervisor/memory/PROJECT_MEMORY.md plus a
# hash-chained provenance entry to .supervisor/memory/.provenance.jsonl, enforces the
# <=200-line cap via write-time eviction, and writes atomically (temp + mv).
#
# ADVISORY memory only — subordinate to the human-authored CLAUDE.md; NEVER an enforcement
# boundary. Promotion is human-gated: callers write only facts a human has approved.
#
# SAFETY INVARIANT (closes red-team F1): refuses to run from a git worktree. Workers run in
# worktrees whose CWD is NOT the repo root; a memory write there would diverge and be lost on
# `git worktree remove`. Only callers at the repo root (Launch Pad, Context-Keeper, main
# thread) may write. The worktree check is the real enforcement, regardless of caller.
#
# CONFIRM NOTE (`--confirm`, REQUIRED for every mutating action): `.supervisor/memory/` is
# UN-IGNORED by `.gitignore` (`!.supervisor/memory/`), so PROJECT_MEMORY.md and .provenance.jsonl
# are TRACKED, COMMITTED files. Until this gate existed, a single non-interactive invocation from
# the repo root appended to the committed store — which is what happened during a review. The
# repo-wide rule this closes: a sole writer whose store is COMMITTED requires --confirm; a writer
# whose store is gitignored does not. The gate is the one already shipped in add-rule.sh and
# add-orientation.sh, cloned verbatim in shape:
#   * `--confirm` passed                         -> proceed;
#   * else an interactive TTY (`-t 0` && `-t 1`)  -> prompt on stderr, accept y/Y/yes/YES;
#   * otherwise                                  -> DRY-RUN: print `PLANNED <ACTION> (not written —
#     pass --confirm to apply):` with the target path and the content, and exit 0 having written
#     NOTHING (store and provenance chain byte-identical).
# It sits AFTER every validation and pre-check — malformed id, unknown retract target, bare
# --supersedes, byte-identical no-op supersede all still FAIL LOUD, because a refusal outranks the
# gate — and BEFORE the first mktemp, so a dry-run creates no temp state either.
#
# Usage:  write-project-memory.sh --fact "<durable fact>" --source "<session_id|agent|user>" --confirm
#         write-project-memory.sh --retract <id> --source "<...>" --confirm
#         write-project-memory.sh --fact "<corrected fact>" --supersedes <id> --source "<...>" --confirm
#
# <id> is EXACTLY 8 lowercase hex chars — the shape this script itself mints (`cut -c1-8` of the
# fact's sha256). Anything else is rejected up front with exit 2 rather than being carried into the
# lookup and reported as the misleading "no memory entry with id".
#
# `--supersedes` is an alias of `--retract` that documents intent WHEN PAIRED with a replacement
# `--fact`. Used WITHOUT one it is a caller mistake — an indistinguishable synonym for a plain
# retraction — and it FAILS CLOSED: exit 2 at validation time, state untouched, with a message
# naming the missing replacement and pointing at `--retract`. That mirrors the sibling store
# (`write-lessons.sh`'s `supersede requires --replacement "<new lesson text>"`, same rationale) so
# the two stores agree deliberately rather than by accident, and it matches the repo-wide
# "correctness gates fail CLOSED" invariant. `--retract` (the honest spelling for a bare retraction)
# is unaffected: still silent, still exit 0.
#
# CORRECTION PATH (--retract / --supersedes): a stored fact can turn out to be WRONG. A raw text
# edit is not an option — the read gate hashes the fact text, so an edited line silently stops
# matching its `add` and is DROPPED without a trace at the call site. `--retract` deletes the
# line AND appends a chain-valid `retract` provenance entry, which read-project-memory.sh honors
# by revoking that content_hash from the trusted set. `--supersedes` is the atomic pair: the
# corrected fact and the retraction of the wrong one commit together or not at all.
#
# Two --supersedes edge semantics (both would otherwise corrupt the index — see the inline notes):
#   * replacement text collides with a DIFFERENT existing entry -> legitimate correction: the
#     retraction runs, the duplicate append + its `add` provenance entry are skipped (dedup).
#   * replacement text is BYTE-IDENTICAL to the target's -> not a correction at all: abort with
#     exit 2, state untouched, so the fact survives (executing it would delete the fact outright).
#
# Exit:   0 on success or safe no-op (e.g. no sha tool); non-zero only on a disallowed /
#         would-corrupt condition (so a bad call can never half-write state). Exit 2 also covers
#         the malformed-call cases rejected at validation time — including a `--supersedes` with no
#         replacement `--fact` — which abort before any temp state exists.

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
  VALIDATOR="${WRITE_PROJECT_MEMORY_VALIDATOR:-}"
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
'       "write-project-memory" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" >&2
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
'       "write-project-memory" "$REFUSE_VALIDATOR_UNAVAILABLE" "$VALIDATOR" "$_ve_src_rc" >&2
    exit 2
  fi

  # Clause (ii). All five are probed, plus the aggregate the call site actually uses — never one
  # name as a proxy for the rest.
  for _vef in $VALIDATOR_REQUIRED_FUNCS validate_entry_all; do
    if ! command -v "$_vef" >/dev/null 2>&1; then
      printf '%s: %s — the shared write-time validator loaded but "%s" is not defined (a partially-loaded validator would report "examined and clean" over half a check), so this entry could not be examined. Nothing was written.
'         "write-project-memory" "$REFUSE_VALIDATOR_UNAVAILABLE" "$_vef" >&2
      exit 2
    fi
  done

  # Clause (iii). Compared against the HARDCODED literal — see the circularity note above.
  if [ "${VALIDATE_ENTRY_CONTRACT:-}" != "$VALIDATE_ENTRY_CONTRACT_REQUIRED" ]; then
    printf '%s: %s — the shared write-time validator contract sentinel is "%s", not the expected "%s" (the file is truncated, or its contract changed), so this entry could not be examined. Nothing was written.
'       "write-project-memory" "$REFUSE_VALIDATOR_UNAVAILABLE" "${VALIDATE_ENTRY_CONTRACT:-<unset>}" "$VALIDATE_ENTRY_CONTRACT_REQUIRED" >&2
    exit 2
  fi
  # ---- LOAD GUARD END -------------------------------------------------------
}


FACT=""; SOURCE="unknown"; RETRACT_ID=""; SUPERSEDES_USED=0; CONFIRM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fact)     FACT="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --fact=*)   FACT="${1#--fact=}"; shift ;;
    --source)   SOURCE="${2:-unknown}"; shift; [ $# -gt 0 ] && shift ;;
    --source=*) SOURCE="${1#--source=}"; shift ;;
    # --retract and --supersedes are the same mechanism; the second name documents intent
    # when it is paired with a replacement --fact. Both keep writing the SAME variable — only the
    # SPELLING the caller used is tracked separately, so the missing-replacement ABORT below can
    # fire for --supersedes without changing anything about --retract.
    # LAST FLAG WINS FOR THE SPELLING TOO: every --retract arm CLEARS the flag, exactly as it
    # overwrites RETRACT_ID. Without that, `--supersedes aaaaaaaa --retract bbbbbbbb` kept a stale
    # SUPERSEDES_USED=1 and the abort below misattributed the caller's spelling — now worse than
    # cosmetic, since it would REJECT (exit 2) an honest bare retraction naming an id ([bbbbbbbb])
    # that was never passed as --supersedes.
    --retract|--supersedes)     if [ "$1" = "--supersedes" ]; then SUPERSEDES_USED=1; else SUPERSEDES_USED=0; fi
                                RETRACT_ID="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --retract=*)                SUPERSEDES_USED=0; RETRACT_ID="${1#--retract=}"; shift ;;
    --supersedes=*)             SUPERSEDES_USED=1; RETRACT_ID="${1#--supersedes=}"; shift ;;
    --confirm)                  CONFIRM=1; shift ;;
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
    *) echo "write-project-memory: unrecognised argument '$1' — refusing rather than writing to a curated store with an argument this writer does not implement (accepted: --fact, --source, --retract, --supersedes, --confirm; see the usage header). Nothing was written." >&2; exit 2 ;;
  esac
done
if [ -z "$FACT" ] && [ -z "$RETRACT_ID" ]; then
  echo "write-project-memory: --fact or --retract <id> is required" >&2; exit 2
fi
# Ids are the first 8 hex chars of the content hash (`cut -c1-8` below), so validate against that
# EXACT shape — positively, not by exclusion.
#
# THIS GATE IS LOAD-BEARING, NOT COSMETIC: the retract-target lookup below interpolates $RETRACT_ID
# into an ANCHORED ERE (`grep -m1 -E -- "^- \[$RETRACT_ID\] "`). That is safe ONLY because the value
# is guaranteed here to be exactly 8 characters drawn from [0-9a-f] — a set that contains no regex
# metacharacter. If this check is ever loosened (longer ids, uppercase, a non-hex alphabet), the
# lookup becomes regex-injectable and must be converted to a literal prefix test (e.g. awk
# `index($0, pfx) == 1`) in the same change. No sed address interpolates the id: the only sed on
# this path is a generic `^- \[[^]]*\] ` bracket-strip, and the deletion below is a literal
# whole-line `grep -vxF` precisely so arbitrary fact text is never read as a pattern.
#
# A length-agnostic check also let a malformed id (e.g. a truncated `--retract a`) sail through to
# the lookup and come back as the misleading "no memory entry with id" instead of "your id is
# malformed".
if [ -n "$RETRACT_ID" ]; then
  case "$RETRACT_ID" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) echo "write-project-memory: --retract id must be exactly 8 lowercase hex chars (got '$RETRACT_ID')" >&2; exit 2 ;;
  esac
fi
# --supersedes without a replacement --fact is a caller mistake: with nothing to supersede it is an
# INDISTINGUISHABLE SYNONYM for a plain retraction. FAIL CLOSED (exit 2), state untouched.
#
# Why not the earlier "warn, never fail": that rationale ("turning it into an error would be a
# breaking change") was false — `--supersedes` ships in this same release and has NO existing
# callers, so no caller can break. Meanwhile the sibling curated store this path mirrors already
# fails closed for the identical operator mistake (write-lessons.sh: `supersede requires
# --replacement "<new lesson text>" (a supersede without a replacement is an indistinguishable
# synonym for retract)`). Two "mirrored" stores disagreeing about the same mistake is the defect;
# the fail-closed precedent wins, matching the repo-wide "correctness gates fail CLOSED" invariant.
# --retract is deliberately exempt: a bare retraction IS the honest meaning of that spelling, so it
# stays silent and exits 0.
#
# ORDERING IS DELIBERATE — argument-shape errors fire BEFORE any state lookup. This abort sits
# above the retract-target resolution, so `--supersedes <unknown-id>` with no --fact reports the
# MISSING REPLACEMENT (the caller's actual mistake) rather than "no memory entry with id". The old
# warning sat at this same point but was non-fatal, so that call first printed "this is a plain
# retraction" and THEN aborted exit 2 at the lookup below — a claim false on its own path (nothing
# was retracted). Being fatal here also means the abort precedes every mktemp, so on this path no
# temp file is ever created and the store is byte-identical.
if [ "$SUPERSEDES_USED" -eq 1 ] && [ -z "$FACT" ]; then
  echo "write-project-memory: --supersedes [$RETRACT_ID] requires a replacement --fact \"<corrected fact>\" (a supersede without a replacement is an indistinguishable synonym for retract) — use --retract if a bare retraction was the intent" >&2
  exit 2
fi
# Sanitize the source label of quotes/backslashes so the no-jq provenance fallback
# (printf-built JSON) can never emit malformed JSONL even if a caller widens --source.
SOURCE="$(printf '%s' "$SOURCE" | tr -d '"\\[:cntrl:]')"
[ -n "$SOURCE" ] || SOURCE="unknown"

# ---- Worktree guard -------------------------------------------------------
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$GITROOT" ] || { echo "write-project-memory: not inside a git repo — refusing" >&2; exit 2; }
# A linked worktree's top-level has a `.git` FILE ("gitdir: ..."); the main checkout has a dir.
if [ -f "$GITROOT/.git" ]; then
  # `.git` as a FILE = a linked WORKTREE or a git SUBMODULE top-level; both refused, both named.
  echo "write-project-memory: refusing to write from a non-primary checkout ($GITROOT) — its top-level '.git' is a FILE, which means either a linked git worktree or a git submodule. Memory is written only from the primary repo root (red-team F1)." >&2
  exit 3
fi
cd "$GITROOT" || { echo "write-project-memory: cannot cd to repo root" >&2; exit 2; }

# ---- sha tool (fail-safe: no tool -> no write) ----------------------------
if command -v sha256sum >/dev/null 2>&1; then   sha() { sha256sum | cut -d' ' -f1; }
elif command -v shasum  >/dev/null 2>&1; then   sha() { shasum -a 256 | cut -d' ' -f1; }
else
  echo "write-project-memory: no sha256 tool (sha256sum/shasum) — writes disabled, fail-safe no-op" >&2
  exit 0
fi

MEM_DIR=".supervisor/memory"
MEM="$MEM_DIR/PROJECT_MEMORY.md"
PROV="$MEM_DIR/.provenance.jsonl"
MAX_LINES="${PROJECT_MEMORY_MAX_LINES:-200}"   # overridable for tests; default = Memory Core Principle cap
GENESIS="GENESIS"

mkdir -p "$MEM_DIR" 2>/dev/null || { echo "write-project-memory: cannot create $MEM_DIR" >&2; exit 2; }
# CONFIRM GATE INTERACTION: creating PROJECT_MEMORY.md / the provenance chain IS a mutation of the
# committed store, so a guaranteed dry-run must not do it either. `CONFIRM=0` with no TTY is
# exactly the case whose gate verdict is already decided here (the prompt branch is unreachable),
# so the bootstrap is skipped and the dry-run leaves the working tree byte-identical — including
# creating no files where there were none. The validator tolerates an absent --store (a clean
# "no prior entries" verdict, not a refusal) and every read below is `2>/dev/null`-guarded or
# `|| true`-ed. An interactive run still bootstraps before prompting: the user is present, and the
# file created is a header-only stub.
if [ "$CONFIRM" -eq 1 ] || { [ -t 0 ] && [ -t 1 ]; }; then
  [ -f "$MEM" ]  || printf '# Project Memory (advisory — subordinate to CLAUDE.md; written only via write-project-memory.sh)\n' > "$MEM"
  [ -f "$PROV" ] || : > "$PROV"
fi

# ---------------------------------------------------------------------------
# THE VALIDATOR CALL SITE (see write-lessons.sh's for the shared rationale). The guard runs on
# every action; the CALL runs only when there is new fact text — a bare `--retract <id>` introduces
# no entry, so there is nothing to examine.
# ---------------------------------------------------------------------------
_ve_load_validator

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
fact_oneline=""; content_hash=""; id=""; fact_present=0
if [ -n "$FACT" ]; then
  fact_oneline="$(printf '%s' "$FACT" | tr '\n' ' ')"
  content_hash="$(printf '%s' "$fact_oneline" | sha)"
  id="$(printf '%s' "$content_hash" | cut -c1-8)"
  # Dedup guard: the id is content-derived, so an identical fact yields an identical entry.
  # Presence is evaluated ONCE and UNCONDITIONALLY here; the boolean then gates only the ADD half
  # below. (It used to be `grep -q ... && [ -z "$RETRACT_ID" ]`, which disabled the CHECK ITSELF on
  # a --supersedes call rather than only its early exit — so the append below wrote a duplicate
  # line whenever the corrected fact already existed elsewhere in the index.)
  # `-x` (WHOLE-LINE) is load-bearing, not tidiness. The stored line is EXACTLY `- [id] <fact>`, so
  # this is an exact comparison by construction — but a bare `grep -F` matches a SUBSTRING, and fact
  # text is arbitrary human prose that can quote the entry shape inline (this repo's own
  # PROJECT_MEMORY.md has entries containing brackets and `- [` sequences). Without `-x`, a fact
  # stored as e.g. "docs say the format is - [7f2a740c] victim entry and that matters" made a
  # genuinely NEW fact "victim entry" look already-present, and the writer discarded it with
  # "fact already present" and exit 0 — silent data loss on a success status.
  if grep -qxF -- "- [$id] $fact_oneline" "$MEM" 2>/dev/null; then fact_present=1; fi
  # A --supersedes call still has work to do (the retraction), so only a bare --fact short-circuits.
  if [ "$fact_present" -eq 1 ] && [ -z "$RETRACT_ID" ]; then
    echo "write-project-memory: fact already present ([$id]) — skipping"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# AC18 — ORDERING. This call sits AFTER the writer's own idempotent dedup short-circuit, and that
# order is the whole point. The dedup guard above is a BENIGN NO-OP: re-writing a fact/lesson/
# contract that is already stored is not an error, it is idempotence, and it has always exited 0.
# Running the validator first turned that into a hard REFUSE_DUPLICATE exit 1, so every idempotent
# caller (a re-run, a retry, a replayed queue item) started failing. The validator's job is to
# examine entries that are about to be WRITTEN; an entry that will not be written has nothing to
# validate. Moving this block above the dedup guard reintroduces the regression.

# ---------------------------------------------------------------------------
# AC18 — ORDERING. This call sits AFTER the writer's own idempotent dedup short-circuit, and that
# order is the whole point. The dedup guard above is a BENIGN NO-OP: re-writing an entry that is
# already stored is idempotence, not an error, and it has always exited 0. Running the validator
# first turned that into a hard REFUSE_DUPLICATE exit 1, so every idempotent caller (a re-run, a
# retry, a replayed queue item) started failing. The validator examines entries about to be
# WRITTEN; an entry that will not be written has nothing to validate. Moving this block back above
# the dedup guard reintroduces the regression — pinned by test.
# AC18, second half: `fact_present` means the ADD half will write nothing (the line is already
# stored). A --supersedes call still has real work to do — the RETRACTION — so it must not be
# refused as a duplicate of the entry it is superseding. Validate only what will actually be
# written; an entry that is already stored is not a new entry.
if [ -n "$FACT" ] && [ "${fact_present:-0}" -eq 0 ]; then
  # ---- VALIDATOR CALL BEGIN -------------------------------------------------
  case "$-" in *e*) _ve_had_e=1 ;; *) _ve_had_e=0 ;; esac
  set +e
  validate_entry_all --entry "$FACT" --store "$MEM" \
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
    1) echo "write-project-memory: refusing to write — the entry was examined and violates a write-time check (see the reason above). Nothing was written." >&2; exit 1 ;;
    *) echo "write-project-memory: refusing to write — the entry COULD NOT BE EXAMINED (see the reason above); refusing rather than reporting it clean. Nothing was written." >&2; exit 2 ;;
  esac
  # ---- VALIDATOR CALL END ---------------------------------------------------
fi

# Resolve the retraction target BEFORE building any temp state, so an unknown id aborts with
# state untouched rather than half-written.
retract_fact=""; retract_hash=""
if [ -n "$RETRACT_ID" ]; then
  # ANCHORED to line start. This is a PREFIX match with an arbitrary suffix (the fact text), so `-x`
  # cannot apply — the anchor has to come from the pattern, which means an ERE rather than -F.
  # Interpolating $RETRACT_ID into a regex is safe ONLY because the validation above guarantees
  # exactly 8 chars from [0-9a-f], which contains no regex metacharacter; loosening that gate makes
  # this line injectable (see the note at the validation block).
  # Why it must be anchored: unanchored, `grep -m1 -F -- "- [$RETRACT_ID] "` matched the MIDDLE of a
  # different entry whose free text quoted that id (e.g. "see - [7f2a740c] for details"). Ordered
  # before the real target, that decoy won `-m1`, and the `grep -vxF "$retract_line"` below then
  # deleted the DECOY while the real entry survived — with provenance recording the real id as
  # retracted. State and provenance disagreed, and the reader still served the "retracted" fact.
  retract_line="$(grep -m1 -E -- "^- \[$RETRACT_ID\] " "$MEM" 2>/dev/null || true)"
  if [ -z "$retract_line" ]; then
    echo "write-project-memory: no memory entry with id [$RETRACT_ID] — nothing to retract, aborting" >&2
    exit 2
  fi
  retract_fact="$(printf '%s' "$retract_line" | sed -E 's/^- \[[^]]*\] //')"
  retract_hash="$(printf '%s' "$retract_fact" | sha)"
fi

# NO-OP SUPERSEDE (semantic: fail CLOSED, state untouched) -------------------
# A --supersedes whose replacement text is byte-identical to the target's is not a correction —
# there is nothing to correct — and executing it DESTROYS the fact two ways over:
#   1. the appended line and the pre-existing one are identical, and the `grep -vxF` below deletes
#      EVERY matching line, so the fact disappears from PROJECT_MEMORY.md entirely; and
#   2. identical text means one shared content_hash, so the `retract` provenance entry revokes the
#      very hash the `add` just trusted and the reader drops the line even if it survived.
# Before this guard the call printed "stored [id]" AND "retracted [id]" and exited 0 — silent data
# loss with a success status. Chosen semantic: abort with exit 2 (same fail-closed convention as the
# unknown-id abort above) BEFORE any temp state exists, so the fact stays in PROJECT_MEMORY.md, the
# reader still returns it, and the caller gets a real error instead of a false "retracted".
# Distinct from the dedup path above: there the replacement collides with a DIFFERENT entry, which
# is a legitimate correction (the retraction runs; only the duplicate append is skipped).
if [ -n "$RETRACT_ID" ] && [ -n "$FACT" ] && [ "$fact_oneline" = "$retract_fact" ]; then
  echo "write-project-memory: --supersedes [$RETRACT_ID] replacement is byte-identical to the target fact — a no-op correction, not a change; aborting with state untouched (the fact is kept)" >&2
  exit 2
fi

# prov_line <id> <prev_hash> <content_hash> <source> <action>
# Emits the JSON with NO trailing newline; callers add exactly one via printf '%s\n'.
# (jq -nc would otherwise append its own newline → blank lines that break the hash chain.)
prov_line() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg id "$1" --arg ph "$2" --arg ch "$3" --arg src "$4" --arg act "$5" --arg ts "$ts" \
      '{id:$id,prev_hash:$ph,content_hash:$ch,source:$src,action:$act,written_at:$ts}' | tr -d '\n'
  else
    printf '{"id":"%s","prev_hash":"%s","content_hash":"%s","source":"%s","action":"%s","written_at":"%s"}' "$1" "$2" "$3" "$4" "$5" "$ts"
  fi
}

# ---------------------------------------------------------------------------
# CONFIRM-ONLY GATE — shape cloned from add-rule.sh (its two `proceed=0` blocks) and
# add-orientation.sh; see the CONFIRM NOTE at the top of the file for WHY this store needs one.
# ONE gate covers this writer's single combined mutation path (add / retract / supersede all commit
# through the same two renames below), so unlike write-lessons.sh there is nothing to factor out.
# Placement: past EVERY refusal — unknown --retract id, bare --supersedes, byte-identical no-op
# supersede, and the validator call — and before the first mktemp, so a dry-run creates no temp
# state and leaves both PROJECT_MEMORY.md and .provenance.jsonl byte-identical.
# ---------------------------------------------------------------------------
if [ -n "$RETRACT_ID" ] && [ -n "$FACT" ]; then _cg_action="SUPERSEDE"
elif [ -n "$RETRACT_ID" ];                then _cg_action="RETRACT"
else                                           _cg_action="WRITE"
fi
proceed=0
if [ "$CONFIRM" -eq 1 ]; then
  proceed=1
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'write-project-memory: %s in %s\n' "$_cg_action" "$MEM" >&2
  [ -n "$RETRACT_ID" ] && printf '  retract: [%s] %s\n' "$RETRACT_ID" "$retract_fact" >&2
  [ -n "$FACT" ]       && printf '  entry: - [%s] %s\n' "$id" "$fact_oneline" >&2
  printf '  source: %s\n' "$SOURCE" >&2
  printf 'Confirm %s? [y/N] ' "$_cg_action" >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) proceed=1 ;; *) proceed=0 ;; esac
fi

if [ "$proceed" -ne 1 ]; then
  printf 'PLANNED %s (not written — pass --confirm to apply):\n' "$_cg_action"
  printf '  target: %s\n' "$MEM"
  printf '  provenance: %s\n' "$PROV"
  [ -n "$RETRACT_ID" ] && printf '  retract: [%s] %s\n' "$RETRACT_ID" "$retract_fact"
  [ -n "$FACT" ]       && printf '  entry: - [%s] %s\n' "$id" "$fact_oneline"
  printf '  source: %s\n' "$SOURCE"
  printf 'write-project-memory: dry-run, pass --confirm to apply (nothing written)\n' >&2
  exit 0
fi

# Temps live IN the memory dir (not $TMPDIR) so the commit `mv` is a same-filesystem,
# truly-atomic rename — a tmpfs /tmp (Linux/CI) would otherwise make `mv` a non-atomic
# cross-device copy+unlink, risking a truncated .provenance.jsonl on interruption.
mem_tmp="$(mktemp "$MEM_DIR/.mtmp.XXXXXX")"; prov_tmp="$(mktemp "$MEM_DIR/.ptmp.XXXXXX")"
trap 'rm -f "$mem_tmp" "$prov_tmp" "$mem_tmp.e" "$mem_tmp.r" 2>/dev/null' EXIT
cat "$MEM" > "$mem_tmp"
cat "$PROV" > "$prov_tmp"

# append_prov <id> <content_hash> <action> — chains off the CURRENT tail of prov_tmp, so
# multiple entries in one commit (supersede = add + retract) each link to their predecessor.
append_prov() {
  _last="$(tail -n1 "$prov_tmp" 2>/dev/null || true)"
  if [ -n "$_last" ]; then _ph="$(printf '%s' "$_last" | sha)"; else _ph="$GENESIS"; fi
  printf '%s\n' "$(prov_line "$1" "$_ph" "$2" "$SOURCE" "$3")" >> "$prov_tmp"
}

# ADD half — skipped when the fact is already in the live index. On a --supersedes that reaches
# here, the RETRACT half below still runs: the correction lands, only the duplicate line (and its
# spurious `add` provenance entry) is suppressed. Skipping the `add` cannot orphan the hash chain —
# append_prov always chains off the CURRENT tail of prov_tmp, so the retract simply links to
# whatever preceded it.
if [ -n "$FACT" ] && [ "$fact_present" -eq 0 ]; then
  printf -- '- [%s] %s\n' "$id" "$fact_oneline" >> "$mem_tmp"
  append_prov "$id" "$content_hash" "add"
fi

if [ -n "$RETRACT_ID" ]; then
  # Delete by exact literal line, not by a sed address — the fact text is arbitrary and would
  # otherwise be interpreted as a regex.
  grep -vxF -- "$retract_line" "$mem_tmp" > "$mem_tmp.r" 2>/dev/null
  mv "$mem_tmp.r" "$mem_tmp" || { echo "write-project-memory: could not remove retracted line" >&2; exit 2; }
  append_prov "$RETRACT_ID" "$retract_hash" "retract"
fi

# ---- Write-time eviction (cap; never silent) ------------------------------
# NOTE: .provenance.jsonl is append-only (one line per add AND per evict), so each read
# walks the full chain (O(n)). Provenance compaction / re-genesis once the log exceeds
# N x cap is a P4 follow-up — fine at the v1 200-entry scale.
count="$(grep -cE '^- \[' "$mem_tmp" 2>/dev/null)"
while [ "$count" -gt "$MAX_LINES" ]; do
  victim="$(grep -nE '^- \[' "$mem_tmp" | head -n1)"
  vid="$(printf '%s' "$victim" | sed -E 's/^[0-9]+:- \[([^]]+)\].*/\1/')"
  awk 'BEGIN{d=0} /^- \[/ && d==0 {d=1; next} {print}' "$mem_tmp" > "$mem_tmp.e" && mv "$mem_tmp.e" "$mem_tmp"
  eph="$(printf '%s' "$(tail -n1 "$prov_tmp")" | sha)"
  printf '%s\n' "$(prov_line "$vid" "$eph" "" "eviction" "evict")" >> "$prov_tmp"
  count="$(grep -cE '^- \[' "$mem_tmp" 2>/dev/null)"
done

# Commit both files. Provenance FIRST: if the second rename fails, the worst case is a
# provenance entry with no matching memory line — which the read-side gate silently ignores
# (no orphaned, repeatedly-logged memory line). A failed first rename leaves state untouched.
mv "$prov_tmp" "$PROV" && mv "$mem_tmp" "$MEM" || {
  echo "write-project-memory: atomic rename failed — write aborted; read gate ignores any unmatched provenance" >&2
  exit 2
}
# THE ADVISORY NOTICE — emitted HERE, past the last reachable refusal and past the atomic commit,
# immediately before the success line. Its sentence ends "...and THE WRITE PROCEEDED", and the
# validator call site above is only on the write PATH: the unknown-retraction-id abort, the
# byte-identical no-op-supersede abort, the retracted-line removal failure and the atomic-rename
# failure all still exit non-zero AFTER it, so emitting there printed "THE WRITE PROCEEDED" and
# then wrote nothing. This is the writer's ONLY success exit, so no genuine write can lose its
# warning; it is a no-op when nothing was reported (or when the validator did not run at all, as on
# a bare `--retract`), so it stays silent rather than wrong on those paths.
validate_entry_advisory_notice "write-project-memory"
# Report what actually happened — never "stored" for a line that was deduped away.
if [ -n "$FACT" ]; then
  if [ "$fact_present" -eq 1 ]; then
    echo "write-project-memory: fact already present ([$id]) — add skipped (dedup), retraction still applied"
  else
    echo "write-project-memory: stored [$id] (source=$SOURCE)"
  fi
fi
[ -n "$RETRACT_ID" ] && echo "write-project-memory: retracted [$RETRACT_ID] (source=$SOURCE)"
exit 0
